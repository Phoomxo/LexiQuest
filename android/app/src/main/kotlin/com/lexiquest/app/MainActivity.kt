package com.lexiquest.app

import android.app.Activity
import android.content.Intent
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val exportChannelName = "com.lexiquest.app/export"
        private const val storageChannelName = "com.lexiquest.app/storage"
    }

    private val exportOwner = Any()
    private val exports get() = NativeExportSession.get(applicationContext)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (applicationContext.packageName == "com.lexiquest.app.ariTest" &&
            (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                "com.lexiquest.app/ari-test").setMethodCallHandler { call, result ->
                if (call.method != "openLogin") {
                    result.notImplemented()
                } else {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://auth.openai.com/codex/device")))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("UNAVAILABLE", "Cannot open login page.", null)
                    }
                }
            }
        }
        exports
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            exportChannelName,
        ).setMethodCallHandler { call, result ->
            exports.dispatch(call, result, exportOwner) { intent ->
                startActivityForResult(intent, NativeExportSession.REQUEST)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "availableBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")?.trim()
            if (path.isNullOrEmpty()) {
                result.error("INVALID_PATH", "Storage path is required.", null)
                return@setMethodCallHandler
            }
            try {
                val canonical = File(path).canonicalFile
                result.success(StatFs(canonical.path).availableBytes)
            } catch (_: IOException) {
                result.error(
                    "UNAVAILABLE",
                    "Filesystem capacity is unavailable.",
                    null,
                )
            } catch (_: IllegalArgumentException) {
                result.error(
                    "UNAVAILABLE",
                    "Filesystem capacity is unavailable.",
                    null,
                )
            } catch (_: SecurityException) {
                result.error(
                    "UNAVAILABLE",
                    "Filesystem capacity is unavailable.",
                    null,
                )
            }
        }
    }

    @Deprecated("Deprecated in Android, retained for the document provider flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == NativeExportSession.REQUEST) {
            exports.activityResult(resultCode == Activity.RESULT_OK, data)
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        exports.detach(exportOwner)
        super.onDestroy()
    }
}
