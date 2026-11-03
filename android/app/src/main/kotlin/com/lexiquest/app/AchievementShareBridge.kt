package com.lexiquest.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID

class AchievementShareBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val shareRequest = 4173
    }
    private val channel = MethodChannel(messenger, "com.lexiquest.app/achievement_share")
    private val directory = File(activity.cacheDir, "achievement-cards")
    private var prepared: Pair<String, File>? = null
    private var pendingResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareAchievementShare" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val signature = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
                    if (bytes == null || bytes.size <= signature.size ||
                        bytes.size > 2 * 1024 * 1024 ||
                        !bytes.copyOfRange(0, signature.size).contentEquals(signature)) {
                        result.error("INVALID_IMAGE", "A bounded PNG image is required.", null)
                    } else {
                        try {
                            prepared?.second?.delete()
                            prepared = null
                            if (!directory.isDirectory && !directory.mkdirs())
                                throw IOException("Image cache unavailable")
                            // Only this bridge's generated cache files are eligible for cleanup.
                            val files = directory.listFiles()?.filter {
                                it.isFile && it.name.matches(Regex("card-[a-f0-9-]+\\.png"))
                            }?.sortedByDescending { it.lastModified() } ?: emptyList()
                            files.forEachIndexed { index, file ->
                                if (index >= 4 || System.currentTimeMillis() - file.lastModified() > 86_400_000)
                                    file.delete()
                            }
                            val token = UUID.randomUUID().toString()
                            val file = File(directory, "card-$token.png")
                            try {
                                file.outputStream().use { it.write(bytes) }
                            } catch (error: IOException) {
                                file.delete()
                                throw error
                            }
                            prepared = token to file
                            result.success(token)
                        } catch (_: IOException) {
                            result.error("UNAVAILABLE", "Cannot prepare the image.", null)
                        } catch (_: SecurityException) {
                            result.error("UNAVAILABLE", "Image cache access denied.", null)
                        }
                    }
                }
                "launchAchievementShare" -> {
                    val selected = prepared
                    if (pendingResult != null || selected == null || call.argument<String>("token") != selected.first ||
                        activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) {
                        result.error("UNAVAILABLE", "The image request is no longer current.", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(
                                activity, "${activity.packageName}.achievementcards", selected.second,
                            )
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "image/png"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newRawUri("LexiQuest achievement", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            pendingResult = result
                            activity.startActivityForResult(Intent.createChooser(intent, "แชร์การ์ดความสำเร็จ").apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, shareRequest)
                            // Retain shared files for receivers; the next preparation bounds this cache.
                            prepared = null
                        } catch (_: ActivityNotFoundException) {
                            pendingResult = null
                            result.error("UNAVAILABLE", "No image sharing app is available.", null)
                        } catch (_: IllegalArgumentException) {
                            pendingResult = null
                            result.error("UNAVAILABLE", "The image provider is unavailable.", null)
                        } catch (_: SecurityException) {
                            pendingResult = null
                            result.error("UNAVAILABLE", "Image sharing access denied.", null)
                        }
                    }
                }
                "discardAchievementShare" -> {
                    if (call.argument<String>("token") == prepared?.first) {
                        prepared?.second?.delete()
                        prepared = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != shareRequest) return false
        val result = pendingResult
        pendingResult = null
        result?.success(null)
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingResult?.error("UNAVAILABLE", "The sharing activity was closed.", null)
        pendingResult = null
        prepared?.second?.delete()
        prepared = null
    }
}
