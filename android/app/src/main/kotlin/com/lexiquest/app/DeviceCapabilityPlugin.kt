package com.lexiquest.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class DeviceCapabilityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var applicationContext: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_SNAPSHOT) {
            result.notImplemented()
            return
        }

        val context = applicationContext
        if (context == null) {
            result.error("channel-unavailable", null, null)
            return
        }

        try {
            result.success(readSnapshot(context))
        } catch (_: Exception) {
            result.error("capability-unavailable", null, null)
        }
    }

    private fun readSnapshot(context: Context): Map<String, Any?> {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: throw DeviceCapabilityUnavailableException()
        val memoryInfo =
            ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val deviceConfiguration = activityManager.deviceConfigurationInfo
        val requestedGlEsVersion = deviceConfiguration.reqGlEsVersion

        return mapOf<String, Any?>(
            "sdkInt" to Build.VERSION.SDK_INT,
            "primaryAbi" to (
                Build.SUPPORTED_ABIS.firstOrNull()?.lowercase(Locale.ROOT) ?: "unknown"
            ),
            "memoryClassMb" to activityManager.memoryClass,
            "availableMemoryMb" to memoryInfo.availMem.let(::bytesToWholeMiB),
            "freeStorageBytes" to StatFs(context.filesDir.absolutePath).availableBytes,
            "lowMemory" to memoryInfo.lowMemory,
            "batterySaverEnabled" to powerManager?.isPowerSaveMode,
            "thermalState" to thermalStateName(powerManager?.currentThermalStatus),
            "gpuApiCandidate" to requestedGlEsVersion?.let {
                it >= MINIMUM_CANDIDATE_GL_ES_VERSION
            },
        )
    }

    private fun thermalStateName(status: Int?): String =
        when (status) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal"
            PowerManager.THERMAL_STATUS_LIGHT,
            PowerManager.THERMAL_STATUS_MODERATE,
            -> "fair"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN,
            -> "critical"
            else -> "unknown"
        }

    private fun bytesToWholeMiB(bytes: Long): Long = bytes / BYTES_PER_MIB

    private companion object {
        const val CHANNEL_NAME = "com.lexiquest.app/device_capabilities"
        const val METHOD_SNAPSHOT = "snapshot"
        const val BYTES_PER_MIB = 1024L * 1024L
        const val MINIMUM_CANDIDATE_GL_ES_VERSION = 0x00030000
    }
}

private class DeviceCapabilityUnavailableException : Exception()
