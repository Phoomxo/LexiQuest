package com.lexiquest.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Executors

/** IPC acknowledgements describe accepted requests, never alarm delivery or OS readback. */
class StudyReminderBridge(activity: Activity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "com.lexiquest.app/study_reminder")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            if (call.method !in setOf("inspect", "bindScope", "schedule", "cancel", "retire")) {
                result.notImplemented()
            } else executor.execute {
                try {
                    val request = Bundle().apply {
                        for (key in listOf("databasePath", "ownerId", "scopeToken"))
                            putString(key, arguments[key] as? String)
                        when (val revision = arguments["revision"]) {
                            is Int -> putLong("revision", revision.toLong())
                            is Long -> putLong("revision", revision)
                        }
                    }
                    val response = context.contentResolver.call(
                        Uri.parse("content://${context.packageName}.studyreminders"),
                        call.method, null, request) ?: throw ReminderRejected("UNAVAILABLE")
                    response.getString("error")?.let { throw ReminderRejected(it) }
                    @Suppress("DEPRECATION")
                    val value = response.keySet().associateWith { response.get(it) }
                    main.post { if (!disposed) result.success(value) }
                } catch (failure: ReminderRejected) {
                    Log.w("LexiQuestReminder", "bridge ${call.method} rejected ${failure.code}")
                    main.post { if (!disposed) result.error(failure.code,
                        "The reminder request is no longer available.", null) }
                } catch (failure: Exception) {
                    Log.w("LexiQuestReminder", "bridge ${call.method} failed ${failure.javaClass.simpleName}")
                    main.post { if (!disposed) result.error("UNAVAILABLE",
                        "Cannot confirm the reminder request.", null) }
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        executor.shutdown()
        // Activity destruction must not switch off a reminder the user enabled.
    }
}

// Android SQLite must not share process-local file locks with Dart's SQLite library.
class StudyReminderProvider : ContentProvider() {
    override fun onCreate() = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        check(Binder.getCallingUid() == android.os.Process.myUid())
        val app = requireNotNull(context)
        return try {
            val value = synchronized(StudyReminderDelivery.lock) {
                when (method) {
                    "inspect" -> mapOf("supported" to true,
                        "notificationsAllowed" to StudyReminderDelivery.allowed(app))
                    "bindScope" -> StudyReminderDelivery.bind(app,
                        extras?.getString("databasePath"), extras?.getString("ownerId"))
                    "retire" -> StudyReminderDelivery.retire(app, extras?.getString("scopeToken"))
                    "schedule", "cancel" -> StudyReminderDelivery.request(app, method,
                        extras?.getString("scopeToken"),
                        if (extras?.containsKey("revision") == true) extras.getLong("revision") else null)
                    else -> throw ReminderRejected("UNAVAILABLE")
                }
            }
            Bundle().apply {
                for ((key, item) in value) when (item) {
                    is Boolean -> putBoolean(key, item)
                    is String -> putString(key, item)
                    is Long -> putLong(key, item)
                    else -> throw ReminderRejected("UNAVAILABLE")
                }
            }
        } catch (failure: ReminderRejected) {
            Log.w("LexiQuestReminder", "provider $method rejected ${failure.code}")
            Bundle().apply { putString("error", failure.code) }
        } catch (failure: Exception) {
            Log.w("LexiQuestReminder", "provider $method failed ${failure.javaClass.simpleName}")
            Bundle().apply { putString("error", "UNAVAILABLE") }
        }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? =
        throw UnsupportedOperationException()
    override fun getType(uri: Uri): String? = throw UnsupportedOperationException()
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?,
        selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}

class StudyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(StudyReminderDelivery.action, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)) return
        val pending = goAsync()
        Thread({
            try {
                synchronized(StudyReminderDelivery.lock) {
                    StudyReminderDelivery.receive(context.applicationContext, intent)
                }
            } catch (_: Exception) {
                // Missing authority, database contention, and invalid data deny delivery.
            } finally { pending.finish() }
        }, "lexiquest-study-reminder").start()
    }
}

private class ReminderRejected(val code: String) : Exception()

private object StudyReminderDelivery {
    val lock = Any()
    const val action = "com.lexiquest.app.STUDY_REMINDER"
    private const val channelId = "study_reminders"
    private const val notificationId = 2701
    private const val requestId = 2701
    private const val fenceKey = "accountDeletion.ownerWriteIntent"
    private val hashPattern = Regex("sha256:[0-9a-f]{64}")
    private data class Setting(val owner: String, val enabled: Boolean, val minute: Int,
        val zone: String, val revision: Long)
    private fun preferences(context: Context) = context.getSharedPreferences(
        "lexiquest-study-reminder-delivery", Context.MODE_PRIVATE)
    private fun reject(): Nothing = throw ReminderRejected("OWNER_CHANGED")
    private fun hash(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    private fun ownerHash(value: String) = "sha256:${hash(value)}"

    fun allowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return manager.areNotificationsEnabled() &&
            manager.getNotificationChannel(channelId)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun privateDatabase(context: Context, path: String?): File {
        if (path.isNullOrBlank() || path.length > 4096) reject()
        val file = File(path).canonicalFile
        val root = File(context.applicationInfo.dataDir).canonicalFile
        if (!file.isFile || !file.path.startsWith(root.path + File.separator)) reject()
        return file
    }

    /** The reserved SQLite transaction fences owner/preference/deletion writes until this read/action ends. */
    private fun <T> read(context: Context, path: String?, action: (SQLiteDatabase, Setting?) -> T): T {
        val file = privateDatabase(context, path)
        return SQLiteDatabase.openDatabase(file.path, null,
            SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING).use { database ->
            database.rawQuery("PRAGMA busy_timeout=2000", null).use { it.moveToFirst() }
            database.beginTransactionNonExclusive()
            try {
                val owners = database.rawQuery("SELECT id FROM local_owners WHERE is_active = 1 LIMIT 2", null)
                    .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
                if (owners.size != 1 || owners[0].isBlank()) reject()
                requireUnfenced(database, owners[0])
                val setting = database.rawQuery("SELECT enabled, minute_of_day, timezone_id, revision " +
                    "FROM study_reminder_preferences WHERE owner_id = ?", arrayOf(owners[0])).use { cursor ->
                    if (!cursor.moveToFirst()) null else {
                        val enabled = cursor.getInt(0)
                        val minute = cursor.getInt(1)
                        val zone = cursor.getString(2)
                        val revision = cursor.getLong(3)
                        if (enabled !in 0..1 || minute !in 0..1439 || revision !in 1..9007199254740991L ||
                            zone.length !in 1..100) reject()
                        ZoneId.of(zone)
                        Setting(owners[0], enabled == 1, minute, zone, revision)
                    }
                }
                action(database, setting)
            } finally { database.endTransaction() } // SELECT-only: never commit application data.
        }
    }

    private fun requireUnfenced(database: SQLiteDatabase, owner: String) {
        database.rawQuery("SELECT bool_value, source, expires_at_utc_ms FROM runtime_flags WHERE key = ?",
            arrayOf(fenceKey)).use { cursor ->
            if (!cursor.moveToFirst()) return
            val source = cursor.getString(1)
            if (cursor.getInt(0) != 1 || !cursor.isNull(2) || source.length > 16384) reject()
            val json = JSONObject(source)
            if (json.opt("version") != 1) reject()
            val phase = json.getString("phase")
            if (phase !in setOf("preparing", "pendingCloud", "cloudConfirmed", "localCompleted")) reject()
            val hasCloud = phase == "cloudConfirmed" || phase == "localCompleted"
            val hasLocal = phase == "localCompleted"
            keys(json, setOf("version", "phase", "ownerBinding", "firebaseUidBinding", "operationBinding",
                "nonceBinding") + (if (hasCloud) setOf("cloudReceipt") else emptySet()) +
                (if (hasLocal) setOf("localReceipt") else emptySet()))
            for (key in listOf("ownerBinding", "firebaseUidBinding", "operationBinding", "nonceBinding"))
                if (!hashPattern.matches(json.getString(key))) reject()
            if (json.getString("ownerBinding") == ownerHash(owner)) reject()
            if (hasCloud) {
                val cloud = json.getJSONObject("cloudReceipt")
                keys(cloud, setOf("receiptId", "ownerId", "firebaseUid", "idempotencyKey", "completedAtUtc"))
                for (key in listOf("receiptId", "ownerId", "firebaseUid")) text(cloud, key)
                val operation = cloud.getString("idempotencyKey")
                if (!hashPattern.matches(operation) || json.getString("operationBinding") != operation ||
                    json.getString("ownerBinding") != ownerHash(cloud.getString("ownerId")) ||
                    json.getString("firebaseUidBinding") != ownerHash(cloud.getString("firebaseUid"))) reject()
                date(cloud.getString("completedAtUtc"))
                val replacement = "local:deleted:" + hash(listOf(cloud.getString("ownerId"),
                    cloud.getString("firebaseUid"), operation, cloud.getString("receiptId"))
                    .joinToString(prefix = "[", postfix = "]", separator = ",", transform = ::dartJsonString))
                if (owner == replacement) reject()
                if (hasLocal) {
                    val local = json.getJSONObject("localReceipt")
                    keys(local, setOf("deletedOwnerId", "newGuestOwnerId", "completedAtUtc"))
                    if (local.getString("deletedOwnerId") != cloud.getString("ownerId") ||
                        local.getString("newGuestOwnerId") != replacement) reject()
                    date(local.getString("completedAtUtc"))
                }
            }
        }
    }

    private fun keys(json: JSONObject, expected: Set<String>) {
        if (json.keys().asSequence().toSet() != expected) reject()
    }
    private fun text(json: JSONObject, key: String) {
        if (json.get(key) !is String || json.getString(key).isBlank()) reject()
    }
    private fun date(value: String) {
        if (!value.endsWith("Z") || Instant.parse(value).isBefore(Instant.EPOCH)) reject()
    }

    // jsonEncode used by accountDeletionReplacementGuestOwnerId leaves slash/non-ASCII intact.
    private fun dartJsonString(value: String): String = buildString {
        append('"')
        for (character in value) when (character) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000C' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (character.code < 32) append("\\u%04x".format(character.code)) else append(character)
        }
        append('"')
    }

    fun bind(context: Context, path: String?, owner: String?): Map<String, Any> {
        if (owner.isNullOrBlank()) reject()
        val file = privateDatabase(context, path)
        return read(context, file.path) { database, _ ->
            val actual = database.rawQuery("SELECT id FROM local_owners WHERE is_active = 1", null)
                .use { it.moveToFirst(); it.getString(0) }
            if (actual != owner) reject()
            cancelAlarm(context)
            val token = UUID.randomUUID().toString()
            if (!preferences(context).edit().clear().putString("databasePath", file.path)
                    .putString("scopeToken", token).putString("ownerHash", ownerHash(owner)).commit())
                throw ReminderRejected("UNAVAILABLE")
            mapOf("scopeToken" to token)
        }
    }

    fun request(context: Context, method: String, token: String?, revision: Long?): Map<String, Any> {
        val prefs = preferences(context)
        if (token.isNullOrBlank() || token != prefs.getString("scopeToken", null)) reject()
        return read(context, prefs.getString("databasePath", null)) { _, setting ->
            if (setting == null || ownerHash(setting.owner) != prefs.getString("ownerHash", null) ||
                setting.revision != revision) reject()
            if (method == "schedule") {
                if (!setting.enabled) reject()
                if (!allowed(context)) throw ReminderRejected("PERMISSION_DENIED")
                val next = schedule(context, token, setting)
                mapOf("accepted" to true, "revision" to setting.revision, "nextAtUtcMs" to next)
            } else {
                if (setting.enabled && allowed(context)) reject()
                cancelAlarm(context)
                prefs.edit().remove("targetUtcMs").remove("revision").commit()
                mapOf("accepted" to true, "revision" to setting.revision)
            }
        }
    }

    fun retire(context: Context, token: String?): Map<String, Any> {
        val prefs = preferences(context)
        val saved = prefs.getString("scopeToken", null)
        if (token != null && token != saved) return mapOf("accepted" to true)
        if (token == null && saved != null) {
            val stillDesired = try {
                read(context, prefs.getString("databasePath", null)) { _, setting ->
                    setting?.enabled == true && ownerHash(setting.owner) == prefs.getString("ownerHash", null)
                }
            } catch (_: Exception) { false }
            if (stillDesired) return mapOf("accepted" to true)
        }
        cancelAlarm(context)
        prefs.edit().remove("scopeToken").remove("ownerHash").remove("revision").remove("targetUtcMs").commit()
        return mapOf("accepted" to true)
    }

    private fun pending(context: Context, token: String, revision: Long, target: Long): PendingIntent =
        PendingIntent.getBroadcast(context, requestId, Intent(context, StudyReminderReceiver::class.java)
            .setAction(action).putExtra("scopeToken", token).putExtra("revision", revision)
            .putExtra("targetUtcMs", target), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun cancelAlarm(context: Context) {
        val intent = PendingIntent.getBroadcast(context, requestId,
            Intent(context, StudyReminderReceiver::class.java).setAction(action),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (intent != null) {
            context.getSystemService(AlarmManager::class.java).cancel(intent)
            intent.cancel()
        }
        context.getSystemService(NotificationManager::class.java).cancel(notificationId)
    }

    private fun schedule(context: Context, token: String, setting: Setting): Long {
        val now = Instant.now()
        val zone = ZoneId.of(setting.zone)
        val time = LocalTime.of(setting.minute / 60, setting.minute % 60)
        var next = now.atZone(zone).toLocalDate().atTime(time).atZone(zone)
        if (!next.toInstant().isAfter(now)) next = next.toLocalDate().plusDays(1).atTime(time).atZone(zone)
        val target = next.toInstant().toEpochMilli()
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channelId, "เตือนทบทวน", NotificationManager.IMPORTANCE_DEFAULT))
        if (!preferences(context).edit().putLong("revision", setting.revision).putLong("targetUtcMs", target).commit())
            throw ReminderRejected("UNAVAILABLE")
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, target, pending(context, token, setting.revision, target))
        return target
    }

    fun receive(context: Context, intent: Intent) {
        val prefs = preferences(context)
        val path = prefs.getString("databasePath", null) ?: return
        try {
            read(context, path) { _, setting ->
                if (setting == null || !setting.enabled || !allowed(context)) {
                    cancelAlarm(context); return@read
                }
                var token = prefs.getString("scopeToken", null)
                if (intent.action == action) {
                    val revision = intent.getLongExtra("revision", -1)
                    val target = intent.getLongExtra("targetUtcMs", -1)
                    if (token == null || token != intent.getStringExtra("scopeToken") ||
                        ownerHash(setting.owner) != prefs.getString("ownerHash", null) ||
                        revision != setting.revision || revision != prefs.getLong("revision", -1) ||
                        target != prefs.getLong("targetUtcMs", -1) || target <= 0 ||
                        System.currentTimeMillis() < target) return@read
                    // Claim this callback before posting. Duplicate/stale callbacks cannot post again.
                    if (!prefs.edit().remove("targetUtcMs").commit()) return@read
                    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    val notification = Notification.Builder(context, channelId)
                        .setSmallIcon(android.R.drawable.ic_popup_reminder)
                        .setContentTitle("LexiQuest").setContentText("พร้อมทบทวนคำศัพท์สักนิดไหม")
                        .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true)
                        .setCategory(Notification.CATEGORY_REMINDER).apply {
                            if (launch != null) setContentIntent(PendingIntent.getActivity(context, requestId,
                                launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                        }.build()
                    context.getSystemService(NotificationManager::class.java).notify(notificationId, notification)
                } else {
                    // Boot/clock changes derive authority from current SQLite rows, never an old token.
                    cancelAlarm(context)
                    token = if (token != null && ownerHash(setting.owner) == prefs.getString("ownerHash", null))
                        token else UUID.randomUUID().toString()
                    if (!prefs.edit().putString("scopeToken", token)
                            .putString("ownerHash", ownerHash(setting.owner)).commit()) return@read
                }
                schedule(context, token!!, setting)
            }
        } catch (_: Exception) { cancelAlarm(context) }
    }
}
