package com.lexiquest.app

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Executors

class StudyReminderBridge(context: Context, messenger: BinaryMessenger) {
    private val application = context.applicationContext
    private val channel = MethodChannel(messenger, "com.lexiquest.app/study_reminder")
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in setOf("status", "enable", "disable", "reconcile")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val arguments = call.arguments as? Map<*, *>
            StudyReminderDelivery.executor.execute {
                try {
                    val path = arguments?.get("databasePath") as? String
                    val owner = arguments?.get("ownerId") as? String
                    val value = when (call.method) {
                        "status" -> StudyReminderDelivery.status(application, path, owner)
                        "enable" -> StudyReminderDelivery.enable(
                            application, path, owner, arguments?.get("preset") as? String,
                        )
                        "disable" -> StudyReminderDelivery.disable(application, path, owner)
                        else -> {
                            StudyReminderDelivery.reconcile(application, path)
                            null
                        }
                    }
                    main.post { if (!disposed) result.success(value) }
                } catch (failure: ReminderFailure) {
                    main.post {
                        if (!disposed) result.error(failure.code, "Study reminder unavailable.", null)
                    }
                } catch (_: Exception) {
                    main.post {
                        if (!disposed) result.error("UNAVAILABLE", "Study reminder unavailable.", null)
                    }
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
    }
}

class StudyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(
                StudyReminderDelivery.alarmAction,
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
            )
        ) return
        val pending = goAsync()
        val application = context.applicationContext
        StudyReminderDelivery.executor.execute {
            try {
                StudyReminderDelivery.receive(application, intent)
            } catch (_: Exception) {
                // A stale intent or unavailable owner cannot authorize a notification.
            } finally {
                pending.finish()
            }
        }
    }
}

private class ReminderFailure(val code: String) : Exception()

private object StudyReminderDelivery {
    val executor = Executors.newSingleThreadExecutor()
    const val alarmAction = "com.lexiquest.app.STUDY_REMINDER"
    private const val channelId = "study_reminders"
    private const val reminderId = 2701
    private const val noDay = Long.MIN_VALUE

    private enum class Preset(val wire: String, val time: LocalTime) {
        WEEKDAYS("weekdaysEvening", LocalTime.of(19, 0)),
        WEEKEND("weekendMorning", LocalTime.of(9, 0));

        fun includes(day: DayOfWeek): Boolean {
            val weekend = day == DayOfWeek.SATURDAY || day == DayOfWeek.SUNDAY
            return weekend == (this == WEEKEND)
        }
    }

    private data class Enrollment(
        val path: String,
        val ownerHash: String,
        val preset: Preset,
        val token: String,
        val target: Long = 0,
        val lastDay: Long = noDay,
    )

    private fun prefs(context: Context) = context.getSharedPreferences(
        "lexiquest-reminder-presets", Context.MODE_PRIVATE,
    )

    private fun notifications(context: Context): NotificationManager =
        checkNotNull(context.getSystemService(NotificationManager::class.java))

    private fun alarms(context: Context): AlarmManager =
        checkNotNull(context.getSystemService(AlarmManager::class.java))

    private fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = notifications(context)
        return manager.areNotificationsEnabled() &&
            manager.getNotificationChannel(channelId)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun preset(wire: String?) = Preset.entries.firstOrNull { it.wire == wire }

    private fun readEnrollment(context: Context): Enrollment? {
        val preferences = prefs(context)
        return Enrollment(
            path = preferences.getString("path", null) ?: return null,
            ownerHash = preferences.getString("ownerHash", null) ?: return null,
            preset = preset(preferences.getString("preset", null)) ?: return null,
            token = preferences.getString("token", null) ?: return null,
            target = preferences.getLong("target", 0),
            lastDay = preferences.getLong("lastDay", noDay),
        )
    }

    private fun writeEnrollment(context: Context, value: Enrollment) {
        val written = prefs(context).edit()
            .putString("path", value.path)
            .putString("ownerHash", value.ownerHash)
            .putString("preset", value.preset.wire)
            .putString("token", value.token)
            .putLong("target", value.target)
            .putLong("lastDay", value.lastDay)
            .commit()
        if (!written) throw ReminderFailure("UNAVAILABLE")
    }

    private fun privateDatabase(context: Context, path: String?): File {
        if (path.isNullOrBlank() || path.length > 4096) throw ReminderFailure("UNAVAILABLE")
        val file = File(path).canonicalFile
        val root = File(context.applicationInfo.dataDir).canonicalFile
        if (!file.isFile || !file.path.startsWith(root.path + File.separator)) {
            throw ReminderFailure("UNAVAILABLE")
        }
        return file
    }

    private fun hashOwner(owner: String): String = MessageDigest.getInstance("SHA-256")
        .digest(owner.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    // The write reservation prevents owner transition during alarm authorization or delivery.
    private fun <T> withOwner(file: File, action: (String?) -> T): T = SQLiteDatabase.openDatabase(
        file.path, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
    ).use { database ->
        database.beginTransactionNonExclusive()
        try {
            val owner = database.rawQuery(
                "SELECT id FROM local_owners WHERE is_active = 1 LIMIT 2", null,
            ).use { cursor ->
                if (!cursor.moveToFirst()) null else {
                    val id = cursor.getString(0)
                    if (cursor.moveToNext() || id.isNullOrBlank()) null else id
                }
            }
            action(owner)
        } finally {
            database.endTransaction()
        }
    }

    private fun requireOwner(owner: String?, expected: String?) {
        if (owner == null || owner != expected) throw ReminderFailure("OWNER_CHANGED")
    }

    private fun status(context: Context, enrollment: Enrollment?) = mapOf(
        "allowed" to allowed(context),
        "preset" to enrollment?.preset?.wire,
    )

    fun status(context: Context, path: String?, expected: String?): Map<String, Any?> {
        val file = privateDatabase(context, path)
        return withOwner(file) { owner ->
            requireOwner(owner, expected)
            status(context, readEnrollment(context)?.takeIf {
                it.path == file.path && it.ownerHash == hashOwner(owner!!)
            })
        }
    }

    fun enable(context: Context, path: String?, expected: String?, wire: String?): Map<String, Any?> {
        val file = privateDatabase(context, path)
        val selected = preset(wire) ?: throw ReminderFailure("INVALID_PRESET")
        return withOwner(file) { owner ->
            requireOwner(owner, expected)
            if (!allowed(context)) throw ReminderFailure("PERMISSION_DENIED")
            val hash = hashOwner(owner!!)
            val previous = readEnrollment(context)?.takeIf { it.path == file.path && it.ownerHash == hash }
            val enrollment = if (previous != null && previous.preset == selected) previous else Enrollment(
                file.path, hash, selected, UUID.randomUUID().toString(), lastDay = previous?.lastDay ?: noDay,
            )
            val schedule = ensureScheduled(context, enrollment, keepTarget = true)
            status(context, schedule)
        }
    }

    fun disable(context: Context, path: String?, expected: String?): Map<String, Any?> {
        val file = privateDatabase(context, path)
        return withOwner(file) { owner ->
            requireOwner(owner, expected)
            retire(context)
            status(context, null)
        }
    }

    fun reconcile(context: Context, path: String?) = restore(context, path, keepTarget = true)

    private fun restore(context: Context, path: String?, keepTarget: Boolean) {
        val enrollment = readEnrollment(context)
        if (enrollment == null) {
            cancel(context)
            return
        }
        val file = privateDatabase(context, path)
        withOwner(file) { owner ->
            if (owner == null || file.path != enrollment.path || enrollment.ownerHash != hashOwner(owner)) {
                retire(context)
            } else if (!allowed(context)) {
                suspendDelivery(context, enrollment)
            } else {
                ensureScheduled(context, enrollment, keepTarget = keepTarget)
            }
        }
    }

    private fun nextTarget(now: Instant, zone: ZoneId, preset: Preset, lastDay: Long): Long {
        val today = now.atZone(zone).toLocalDate()
        return (0L..7L).asSequence().map(today::plusDays).filter { day ->
            day.toEpochDay() != lastDay && preset.includes(day.dayOfWeek)
        }.map { it.atTime(preset.time).atZone(zone).toInstant() }
            .first { it.isAfter(now) }.toEpochMilli()
    }

    private fun targetDay(target: Long, now: Instant, zone: ZoneId, preset: Preset): LocalDate? {
        if (target <= 0) return null
        val intended = Instant.ofEpochMilli(target).atZone(zone)
        val day = intended.toLocalDate()
        if (!preset.includes(day.dayOfWeek) ||
            day.atTime(preset.time).atZone(zone).toInstant() != intended.toInstant() ||
            day.isBefore(now.atZone(zone).toLocalDate())
        ) return null
        return day
    }

    private fun ensureScheduled(context: Context, value: Enrollment, keepTarget: Boolean): Enrollment {
        val now = Instant.now()
        val zone = ZoneId.systemDefault()
        val existingDay = targetDay(value.target, now, zone, value.preset)
        val scheduled = if (keepTarget && existingDay != null && existingDay.toEpochDay() != value.lastDay) {
            value
        } else {
            value.copy(target = nextTarget(now, zone, value.preset, value.lastDay))
        }
        notifications(context).createNotificationChannel(
            NotificationChannel(channelId, "เตือนทบทวน", NotificationManager.IMPORTANCE_DEFAULT),
        )
        val intent = alarmIntent(context)
            .putExtra("token", scheduled.token)
            .putExtra("target", scheduled.target)
        val pending = PendingIntent.getBroadcast(
            context, reminderId, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, scheduled.target, pending)
        try {
            writeEnrollment(context, scheduled)
        } catch (failure: ReminderFailure) {
            cancel(context)
            throw failure
        }
        return scheduled
    }

    private fun alarmIntent(context: Context) = Intent(context, StudyReminderReceiver::class.java)
        .setAction(alarmAction)

    private fun cancel(context: Context) {
        val pending = PendingIntent.getBroadcast(
            context, reminderId, alarmIntent(context), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) {
            alarms(context).cancel(pending)
            pending.cancel()
        }
        notifications(context).cancel(reminderId)
    }

    private fun retire(context: Context) {
        val cleared = prefs(context).edit().clear().commit()
        cancel(context)
        if (!cleared) throw ReminderFailure("UNAVAILABLE")
    }

    private fun suspendDelivery(context: Context, enrollment: Enrollment) {
        cancel(context)
        if (enrollment.target != 0L) writeEnrollment(context, enrollment.copy(target = 0))
    }

    fun receive(context: Context, intent: Intent) {
        val enrollment = readEnrollment(context) ?: return
        if (intent.action != alarmAction) {
            restore(context, enrollment.path, keepTarget = false)
            return
        }
        if (intent.getStringExtra("token") != enrollment.token ||
            intent.getLongExtra("target", -1) != enrollment.target
        ) return
        val file = privateDatabase(context, enrollment.path)
        withOwner(file) { owner ->
            if (owner == null || enrollment.ownerHash != hashOwner(owner)) {
                retire(context)
                return@withOwner
            }
            if (!allowed(context)) {
                suspendDelivery(context, enrollment)
                return@withOwner
            }
            val now = Instant.now()
            val zone = ZoneId.systemDefault()
            val day = targetDay(enrollment.target, now, zone, enrollment.preset)
            if (day == null || day.toEpochDay() == enrollment.lastDay) {
                ensureScheduled(context, enrollment, keepTarget = false)
                return@withOwner
            }
            if (now.toEpochMilli() < enrollment.target) return@withOwner
            // Persist the claim and arm the next occurrence before posting this one.
            ensureScheduled(context, enrollment.copy(lastDay = day.toEpochDay()), keepTarget = false)
            post(context)
        }
    }

    private fun post(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("LexiQuest")
            .setContentText("ถึงเวลาทบทวนคำศัพท์")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
        if (launch != null) {
            notification.setContentIntent(PendingIntent.getActivity(
                context, reminderId, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
        }
        notifications(context).notify(reminderId, notification.build())
    }
}
