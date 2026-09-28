package com.lexiquest.app

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Only packaged for isolated native draft debug variants. */
class NativeDraftActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        // Register only the two local test dependencies. In particular, never
        // register Firebase/auth, Workmanager, camera, TTS or external URL plugins.
        engine.plugins.add(io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin())
        engine.plugins.add(dev.flutter.plugins.integration_test.IntegrationTestPlugin())
        MethodChannel(engine.dartExecutor.binaryMessenger, "lexiquest/native-draft")
            .setMethodCallHandler { call, result ->
                val run = intent.getStringExtra("baselineRun") ?: ""
                val phase = intent.getStringExtra("baselinePhase") ?: ""
                val expectedPackage = when {
                    run.startsWith("cb-") -> "com.lexiquest.app.nativeDraftCb"
                    run.startsWith("cd-") -> "com.lexiquest.app.nativeDraftCd"
                    run.startsWith("ce-") -> "com.lexiquest.app.nativeDraftCe"
                    else -> ""
                }
                if (packageName != expectedPackage ||
                    (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0 ||
                    !Regex("^(cb|cd|ce)-[a-z0-9-]{1,48}$").matches(run) ||
                    phase !in listOf("seed", "resume")) {
                    result.error("REJECTED", "Invalid isolated baseline context", null)
                } else if (call.method == "context") {
                    result.success(mapOf("packageId" to packageName, "runId" to run,
                        "phase" to phase, "supportPath" to filesDir.canonicalPath))
                } else result.notImplemented()
            }
    }
}
