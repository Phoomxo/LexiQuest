package com.lexiquest.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One process-wide export slot. All state transitions/replies run on the main loop.
 * Provider and durable journal I/O run on one worker, with no unbounded work queue:
 * the slot stays occupied even after a timeout until that worker actually returns.
 * A provider that ignores interruption cannot be safely declared cancelled/removed.
 */
internal class NativeExportSession(context: Context) {
    companion object {
        const val REQUEST = 4172
        const val MAX_BYTES = 16 * 1024 * 1024
        private const val PICKER = "pending-picker"
        private const val JOURNAL = "uncommitted"
        private const val WRITE_TIMEOUT_MS = 30_000L
        private var instance: NativeExportSession? = null
        fun get(context: Context): NativeExportSession = instance
            ?: NativeExportSession(context.applicationContext).also { instance = it }
    }

    private class Operation(val id: String, val owner: Any, var bytes: ByteArray?, var reply: MethodChannel.Result?) {
        val cancelled = AtomicBoolean(false)
        var location: String? = null
        var picking = false
        var ready = false
        var watchdog: Runnable? = null
    }
    private val resolver = context.contentResolver
    private val preferences = context.getSharedPreferences("export-recovery", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "lexiquest-export").apply { isDaemon = true } }
    private var operation: Operation? = null
    private var busy = false
    private var waitingForOldPicker = false
    private var recoveryFailed = false
    private var recovering = false
    private var deferredPicker: Pair<Boolean, Intent?>? = null

    init { recover() }

    // Worker only. A journal entry is removed only after deletion or explicit commit.
    private fun journal(): Set<String> = preferences.getStringSet(JOURNAL, emptySet())!!.toSet()
    private fun record(entries: Set<String>) {
        if (!preferences.edit().putStringSet(JOURNAL, entries).commit()) throw IOException("Export journal unavailable")
    }
    private fun discard(location: String): Boolean = try {
        val uri = Uri.parse(location)
        if (!DocumentsContract.deleteDocument(resolver, uri)) false else {
            record(journal() - location)
            try { resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
            true
        }
    } catch (_: Exception) { false }

    private fun recover() {
        if (busy || operation != null) return
        busy = true
        recovering = true
        worker.execute {
            var failed = false
            var picker = false
            try {
                val entries = journal()
                picker = PICKER in entries
                for (location in entries - PICKER) if (!discard(location)) failed = true
            } catch (_: Exception) { failed = true }
            main.post {
                waitingForOldPicker = picker
                recoveryFailed = failed
                busy = false
                recovering = false
                val deferred = deferredPicker
                deferredPicker = null
                if (deferred != null) activityResult(deferred.first, deferred.second)
            }
        }
    }

    fun dispatch(call: MethodCall, result: MethodChannel.Result, owner: Any, launch: (Intent) -> Unit) {
        when (call.method) {
            "cancelExportFile" -> {
                val op = operation
                if (op != null && op.id == call.argument<String>("operationId") && op.owner === owner) cancel(op)
                // Acknowledges the request, not completion or cleanup. save/finish owns that receipt.
                result.success(null)
            }
            "finishExportFile" -> finish(call, result, owner)
            "saveExportFile" -> {
                val name = call.argument<String>("suggestedName")?.substringAfterLast('/')?.substringAfterLast('\\')?.trim()
                val mime = call.argument<String>("mimeType")?.trim()
                val bytes = call.argument<ByteArray>("bytes")
                val id = call.argument<String>("operationId") ?: "legacy"
                if (name.isNullOrEmpty() || mime.isNullOrEmpty() || bytes == null) {
                    result.error("WRITE_FAILED", "Invalid export payload.", null); return
                }
                if (bytes.size > MAX_BYTES) {
                    result.error("PAYLOAD_TOO_LARGE", "Android export is limited to 16 MiB. Choose a smaller export.", null); return
                }
                if (recoveryFailed) {
                    result.error("CLEANUP_FAILED", "An earlier document still needs cleanup.", null)
                    recover(); return
                }
                if (operation != null || busy || waitingForOldPicker) {
                    result.error("UNAVAILABLE", "An export or its cleanup is still pending.", null); return
                }
                val op = Operation(id, owner, bytes, result)
                operation = op; busy = true
                worker.execute {
                    val recorded = try { record(journal() + PICKER); true } catch (_: Exception) { false }
                    main.post {
                        busy = false
                        if (!recorded || op.cancelled.get()) {
                            abandonPicker(op, if (recorded) "CANCELLED" else "WRITE_FAILED")
                        } else {
                            op.picking = true
                            try {
                                launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE); type = mime
                                    putExtra(Intent.EXTRA_TITLE, name)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                })
                            } catch (_: Exception) { abandonPicker(op, "UNAVAILABLE") }
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(op: Operation, code: String?, value: Any? = null) {
        val result = op.reply ?: return
        op.reply = null
        if (code == null) result.success(value) else result.error(code, "Export did not complete ($code).", null)
    }
    private fun stopWatch(op: Operation) { op.watchdog?.let { main.removeCallbacks(it) }; op.watchdog = null }
    private fun watch(op: Operation) {
        val timer = Runnable {
            op.cancelled.set(true)
            reply(op, "CLEANUP_FAILED")
            // Keep slot/journal: timeout does not prove the provider stopped or deleted anything.
        }
        op.watchdog = timer
        main.postDelayed(timer, WRITE_TIMEOUT_MS)
    }
    private fun abandonPicker(op: Operation, code: String) {
        busy = true
        worker.execute {
            val cleared = try { record(journal() - PICKER); true } catch (_: Exception) { false }
            main.post {
                busy = false; operation = null; op.bytes = null
                recoveryFailed = !cleared
                reply(op, if (cleared) code else "CLEANUP_FAILED")
            }
        }
    }
    private fun cancel(op: Operation) {
        op.cancelled.set(true)
        if (op.picking) {
            op.bytes = null
            reply(op, "CANCELLED")
            // Keep the picker tombstone; a late URI is ours to remove, never a new save's URI.
        } else if (op.ready && !busy) {
            cleanupReady(op)
        }
    }
    fun detach(owner: Any) { operation?.takeIf { it.owner === owner }?.let { cancel(it) } }

    fun activityResult(ok: Boolean, data: Intent?) {
        if (recovering) {
            if (deferredPicker == null) deferredPicker = Pair(ok, data)
            return
        }
        val op = operation
        if (op == null && !waitingForOldPicker) return
        if (op != null && !op.picking) return // Duplicate result cannot start a second worker.
        if (busy) return
        val location = if (ok) data?.data?.toString() else null
        waitingForOldPicker = false
        if (op != null) op.picking = false
        busy = true
        if (op != null) { op.location = location; watch(op) }
        worker.execute {
            var code: String? = null
            try {
                // Replace the picker marker with the URI before touching provider bytes.
                record((journal() - PICKER) + listOfNotNull(location))
                if (location != null) {
                    val uri = Uri.parse(location)
                    try {
                        resolver.takePersistableUriPermission(uri, (data?.flags ?: 0) and
                            (Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    } catch (_: Exception) { /* Provider may not support persistence; retain URI and report failed recovery if access is lost. */ }
                    if (op == null || op.cancelled.get()) {
                        code = if (discard(location)) "CANCELLED" else "CLEANUP_FAILED"
                    } else {
                        val bytes = op.bytes ?: throw IOException("Missing export bytes")
                        val stream = resolver.openOutputStream(uri, "w") ?: throw IOException("No provider stream")
                        stream.use {
                            var offset = 0
                            while (offset < bytes.size) {
                                if (op.cancelled.get()) throw ExportCancelled()
                                val count = minOf(64 * 1024, bytes.size - offset)
                                it.write(bytes, offset, count); offset += count
                            }
                            if (op.cancelled.get()) throw ExportCancelled()
                            it.flush()
                        } // Close is part of the success boundary and stays on the worker.
                        if (op.cancelled.get()) throw ExportCancelled()
                    }
                }
            } catch (error: Exception) {
                code = when {
                    location != null && !discard(location) -> "CLEANUP_FAILED"
                    error is ExportCancelled -> "CANCELLED"
                    error is SecurityException -> "PERMISSION_DENIED"
                    outOfSpace(error) -> "INSUFFICIENT_SPACE"
                    else -> "WRITE_FAILED"
                }
            }
            val outcome = code
            main.post {
                busy = false
                if (op == null) { recoveryFailed = outcome == "CLEANUP_FAILED"; return@post }
                stopWatch(op); op.bytes = null
                if (outcome == null && location != null) {
                    op.ready = true
                    if (op.cancelled.get()) cleanupReady(op) else reply(op, null, location)
                } else {
                    operation = null; recoveryFailed = outcome == "CLEANUP_FAILED"
                    reply(op, outcome, null)
                }
            }
        }
    }

    private fun cleanupReady(op: Operation) {
        val result = object: MethodChannel.Result {
            override fun success(value: Any?) { reply(op, "CANCELLED") }
            override fun error(code: String, message: String?, details: Any?) { reply(op, code) }
            override fun notImplemented() { reply(op, "CLEANUP_FAILED") }
        }
        finishDocument(op, true, result)
    }
    private fun finish(call: MethodCall, result: MethodChannel.Result, owner: Any) {
        val op = operation
        val discard = call.argument<Boolean>("discard")
        if (op == null || op.owner !== owner || !op.ready || busy || discard == null || op.location != call.argument<String>("location")) {
            result.error("CLEANUP_FAILED", "Unknown or unsettled export document.", null); return
        }
        // Commit is the linearization point: cancellation after this admission cannot revoke it.
        finishDocument(op, discard || op.cancelled.get(), result)
    }
    private fun finishDocument(op: Operation, discard: Boolean, result: MethodChannel.Result) {
        busy = true; op.ready = false
        var replied = false
        val timeout = Runnable { if (!replied) { replied = true; result.error("CLEANUP_FAILED", "Document settlement is still pending.", null) } }
        main.postDelayed(timeout, WRITE_TIMEOUT_MS)
        worker.execute {
            val ok = try {
                if (discard) discard(op.location!!) else {
                    record(journal() - op.location!!)
                    try { resolver.releasePersistableUriPermission(Uri.parse(op.location!!), Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) { }
                    true
                }
            } catch (_: Exception) { false }
            main.post {
                main.removeCallbacks(timeout); busy = false; operation = null; recoveryFailed = !ok
                if (!replied) {
                    replied = true
                    if (ok) result.success(null) else result.error("CLEANUP_FAILED", "Document settlement failed.", null)
                }
            }
        }
    }
    private class ExportCancelled: IOException()
    private fun outOfSpace(error: Throwable): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is ErrnoException && cause.errno == OsConstants.ENOSPC) return true
            cause = cause.cause
        }
        return false
    }
}
