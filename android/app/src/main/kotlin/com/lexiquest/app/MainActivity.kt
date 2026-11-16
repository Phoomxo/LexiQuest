package com.lexiquest.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.system.ErrnoException
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val exportChannelName = "com.lexiquest.app/export"
        private const val createExportDocumentRequest = 4172
    }

    private data class SelectedExportDestination(
        val uri: Uri,
        val token: String,
    )

    private var pendingExportResult: MethodChannel.Result? = null
    private var selectedExportDestination: SelectedExportDestination? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            exportChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "selectExportDestination" -> selectExportDestination(call, result)
                "writeExportFile" -> writeExportFile(call, result)
                "discardExportDestination" -> discardExportDestination(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun selectExportDestination(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (pendingExportResult != null) {
            result.error(
                "UNAVAILABLE",
                "Another export is already waiting for a destination.",
                null,
            )
            return
        }

        val suggestedName = call.argument<String>("suggestedName")
            ?.substringAfterLast('/')
            ?.substringAfterLast('\\')
            ?.trim()
        val mimeType = call.argument<String>("mimeType")?.trim()
        if (suggestedName.isNullOrEmpty() || mimeType.isNullOrEmpty()) {
            result.error("WRITE_FAILED", "Invalid export metadata.", null)
            return
        }

        selectedExportDestination = null
        pendingExportResult = result
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

    private fun writeExportFile(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val destination = call.argument<String>("destination")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let(Uri::parse)
        val selectionToken = call.argument<String>("selectionToken")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val bytes = call.argument<ByteArray>("bytes")
        val selected = selectedExportDestination
        if (
            destination == null ||
            selectionToken == null ||
            bytes == null ||
            selected == null ||
            destination != selected.uri ||
            selectionToken != selected.token
        ) {
            result.error("UNAVAILABLE", "The export destination is stale.", null)
            return
        }
        selectedExportDestination = null

        try {
            val stream = contentResolver.openOutputStream(destination, "w")
                ?: throw IOException("Document provider returned no stream.")
            stream.use {
                it.write(bytes)
                it.flush()
            }
            result.success(null)
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

    private fun discardExportDestination(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val destination = call.argument<String>("destination")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let(Uri::parse)
        val selectionToken = call.argument<String>("selectionToken")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val selected = selectedExportDestination
        if (
            destination == null ||
            selectionToken == null ||
            selected == null ||
            destination != selected.uri ||
            selectionToken != selected.token
        ) {
            result.error("UNAVAILABLE", "The export destination is stale.", null)
            return
        }
        selectedExportDestination = null
        result.success(null)
    }

    @Deprecated("Deprecated in Android, retained for the document provider flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != createExportDocumentRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingExportResult
        clearPendingExport()
        if (result == null) {
            return
        }
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            selectedExportDestination = null
            result.success(null)
            return
        }
        val selected = SelectedExportDestination(
            uri = destination,
            token = UUID.randomUUID().toString(),
        )
        selectedExportDestination = selected
        result.success(
            mapOf(
                "destination" to selected.uri.toString(),
                "selectionToken" to selected.token,
            ),
        )
    }

    private fun clearPendingExport() {
        pendingExportResult = null
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
