package com.lexiquest.app

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Only packaged when nativeBaselineTest=true; no production export/auth UI. */
class NativeBaselineActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        // Register only the two local test dependencies. In particular, never
        // register Firebase/auth, Workmanager, camera, TTS or external URL plugins.
        engine.plugins.add(io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin())
        engine.plugins.add(dev.flutter.plugins.integration_test.IntegrationTestPlugin())
        MethodChannel(engine.dartExecutor.binaryMessenger, "lexiquest/native-baseline")
            .setMethodCallHandler { call, result ->
                val run = intent.getStringExtra("baselineRun") ?: ""
                val phase = intent.getStringExtra("baselinePhase") ?: ""
                if (packageName != "com.lexiquest.app.nativeBaselineBm" ||
                    (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0 ||
                    !Regex("^bm-[a-z0-9-]{1,48}$").matches(run) ||
                    phase !in listOf("seed", "verify")) {
                    result.error("REJECTED", "Invalid isolated baseline context", null)
                } else if (call.method == "context") {
                    result.success(mapOf("packageId" to packageName, "runId" to run,
                        "phase" to phase, "supportPath" to filesDir.canonicalPath))
                } else result.notImplemented()
            }
    }
}
