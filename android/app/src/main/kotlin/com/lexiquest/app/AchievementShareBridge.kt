package com.lexiquest.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class AchievementShareFileProvider : FileProvider()

internal class AchievementShareBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "com.lexiquest.app/achievement_share")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "sharePng") {
                sharePng(call.arguments as? ByteArray, result)
            } else {
                result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun sharePng(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || !isBoundedPng(bytes)) {
            result.error("INVALID_IMAGE", "The card image is invalid.", null)
            return
        }
        val send = Intent(Intent.ACTION_SEND).setType("image/png")
        var staged: File? = null
        var opened = false
        try {
            if (!canLaunch() ||
                activity.packageManager.queryIntentActivities(send, PackageManager.MATCH_DEFAULT_ONLY)
                    .isEmpty()
            ) {
                result.error("UNAVAILABLE", "No share target is available.", null)
                return
            }
            val directory = File(activity.cacheDir, "achievement-share")
            if (!directory.isDirectory && !directory.mkdirs()) {
                throw IOException("Share cache directory is unavailable.")
            }
            pruneCache(directory)
            val file = File.createTempFile("lexiquest-", ".png", directory).also { staged = it }
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.achievement-share",
                file,
            )
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.clipData = ClipData.newRawUri("LexiQuest", uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (!canLaunch()) {
                result.error("UNAVAILABLE", "The app is no longer in the foreground.", null)
                return
            }
            activity.startActivity(Intent.createChooser(send, null))
            opened = true
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("UNAVAILABLE", "The system share sheet is unavailable.", null)
        } catch (_: IOException) {
            result.error("SHARE_FAILED", "The card image could not be prepared.", null)
        } catch (_: IllegalArgumentException) {
            result.error("SHARE_FAILED", "The card image could not be opened.", null)
        } catch (_: SecurityException) {
            result.error("SHARE_FAILED", "The card image could not be shared.", null)
        } finally {
            if (!opened) staged?.delete()
        }
    }

    private fun canLaunch(): Boolean =
        !activity.isFinishing && !activity.isDestroyed && activity.hasWindowFocus()

    private fun isBoundedPng(bytes: ByteArray): Boolean {
        if (bytes.size !in 33..2 * 1024 * 1024) return false
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        return bounds.outMimeType == "image/png" &&
            bounds.outWidth in 1..2048 && bounds.outHeight in 1..2048
    }

    private fun pruneCache(directory: File) {
        val cached = directory.listFiles { file ->
            file.isFile && file.name.startsWith("lexiquest-") && file.extension == "png"
        } ?: throw IOException("Share cache could not be read.")
        val now = System.currentTimeMillis()
        val freshFor = TimeUnit.HOURS.toMillis(1)
        // shortcut: prune this private cache on share, add idle cleanup if images require prompt erasure.
        cached.sortedByDescending { it.lastModified() }.forEachIndexed { index, file ->
            if ((index >= 3 || now - file.lastModified() !in 0L until freshFor) && !file.delete()) {
                throw IOException("Share cache could not be pruned.")
            }
        }
    }
}
