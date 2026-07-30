package com.lexiquest.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val exportChannelName = "com.lexiquest.app/export"
        private const val createExportDocumentRequest = 4172
    }

    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            exportChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveExportFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingExportResult != null) {
                result.error(
                    "UNAVAILABLE",
                    "Another export is already waiting for a destination.",
                    null,
                )
                return@setMethodCallHandler
            }

            val suggestedName = call.argument<String>("suggestedName")
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.trim()
            val mimeType = call.argument<String>("mimeType")?.trim()
            val bytes = call.argument<ByteArray>("bytes")
            if (
                suggestedName.isNullOrEmpty() ||
                mimeType.isNullOrEmpty() ||
                bytes == null
            ) {
                result.error("WRITE_FAILED", "Invalid export payload.", null)
                return@setMethodCallHandler
            }

            pendingExportResult = result
            pendingExportBytes = bytes
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, suggestedName)
            }
            try {
                startActivityForResult(intent, createExportDocumentRequest)
            } catch (_: ActivityNotFoundException) {
                clearPendingExport()
                result.error(
                    "UNAVAILABLE",
                    "No document provider is available.",
                    null,
                )
            }
        }
    }

    @Deprecated("Deprecated in Android, retained for the document provider flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != createExportDocumentRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingExportResult
        val bytes = pendingExportBytes
        clearPendingExport()
        if (result == null || bytes == null) {
            return
        }
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            result.success(null)
            return
        }

        try {
            val stream = contentResolver.openOutputStream(destination, "w")
                ?: throw IOException("Document provider returned no stream.")
            stream.use {
                it.write(bytes)
                it.flush()
            }
            result.success(destination.toString())
        } catch (_: SecurityException) {
            result.error(
                "PERMISSION_DENIED",
                "The document provider denied write access.",
                null,
            )
        } catch (error: IOException) {
            val code = if (isOutOfSpace(error)) {
                "INSUFFICIENT_SPACE"
            } else {
                "WRITE_FAILED"
            }
            result.error(code, "The export file could not be written.", null)
        }
    }

    private fun clearPendingExport() {
        pendingExportResult = null
        pendingExportBytes = null
    }

    private fun isOutOfSpace(error: Throwable): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (
                cause is ErrnoException &&
                cause.errno == OsConstants.ENOSPC
            ) {
                return true
            }
            cause = cause.cause
        }
        return false
    }
}
