package com.example.step_counter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar

class StepTrackingService : Service(), SensorEventListener {

    companion object {
        private const val TAG = "StepTrackingService"
        const val CHANNEL_ID = "step_tracking_channel"
        private const val NOTIFICATION_ID = 1

        const val PREFS_NAME = "step_counter_prefs"
        const val KEY_TRACKING_ENABLED = "tracking_enabled"

        const val KEY_RETENTION_MODE = "retention_policy_mode" // NEVER | DAYS
        const val KEY_RETENTION_DAYS = "retention_policy_days" // Int
        const val KEY_RETENTION_LAST_CLEANUP = "retention_last_cleanup_at" // Long (millis)

        private const val KEY_LAST_SENSOR_VALUE = "last_sensor_value"

        private const val KEY_DAY_TOTAL_PREFIX = "day_total_"      // + dateKey
        private const val KEY_DAY_HOURLY_PREFIX = "day_hour_"      // + dateKey + "_<hour>"

        private const val KEY_DAILY_GOAL_STEPS = "daily_goal_steps"
        private const val KEY_GOAL_LAST_NOTIFIED_DATE = "goal_last_notified_date"
        const val KEY_GOAL_NOTIFICATION_ENABLED = "goal_notification_enabled"

        private const val DEFAULT_GOAL_STEPS = 8000

        private const val KEY_GOAL_ACHIEVED_PREFIX = "goal_achieved_" // + dateKey

        const val ACTION_STEPS_UPDATED =
            "com.example.step_counter.STEPS_UPDATED"
        const val EXTRA_TODAY_STEPS = "extra_today_steps"
    }

    private lateinit var sensorManager: SensorManager
    private var stepCounterSensor: Sensor? = null
    private lateinit var prefs: SharedPreferences

    private fun isTrackingEnabled(): Boolean {
        return prefs.getBoolean(KEY_TRACKING_ENABLED, true)
    }

    private fun getDailyGoalSteps(): Int {
        return prefs.getInt(KEY_DAILY_GOAL_STEPS, DEFAULT_GOAL_STEPS)
    }

    private fun isGoalNotificationEnabled(): Boolean {
        return prefs.getBoolean(KEY_GOAL_NOTIFICATION_ENABLED, true)
    }

    private fun hasSentGoalNotificationFor(dateKey: String): Boolean {
        val last = prefs.getString(KEY_GOAL_LAST_NOTIFIED_DATE, null)
        return last == dateKey
    }

    private fun markGoalNotificationSent(dateKey: String) {
        prefs.edit()
            .putString(KEY_GOAL_LAST_NOTIFIED_DATE, dateKey)
            .apply()
    }

    private fun checkAndNotifyGoalReached(todaySteps: Int) {
        if (!isGoalNotificationEnabled()) return

        val goal = getDailyGoalSteps()
        if (goal <= 0) return
        if (todaySteps < goal) return

        val dateKey = currentDayKey()
        if (hasSentGoalNotificationFor(dateKey)) return

        val prettyDate = try {
            val localDate = LocalDate.parse(dateKey, DateTimeFormatter.ISO_LOCAL_DATE)
            localDate.format(DateTimeFormatter.ofPattern("dd.MM.yyyy"))
        } catch (e: Exception) {
            dateKey
        }

        val title = "Dzisiejszy cel osiągnięty"
        val text = "Dzisiejszy cel ($prettyDate – $goal kroków) osiągnięty. Gratulacje!"

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Śledzenie kroków",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            manager.createNotificationChannel(channel)
        }

        val openIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        manager.notify(1001, notification)

        markGoalNotificationSent(dateKey)

        markDailyGoalAchieved(dateKey, goal)
    }

    private fun markDailyGoalAchieved(dateKey: String, goal: Int) {
        prefs.edit()
            .putInt("$KEY_GOAL_ACHIEVED_PREFIX$dateKey", goal)
            .apply()
    }

    private fun runRetentionCleanupIfNeeded() {
        if (!::prefs.isInitialized) return

        val mode = prefs.getString(KEY_RETENTION_MODE, "NEVER") ?: "NEVER"
        if (mode != "DAYS") return

        val keepDays = prefs.getInt(KEY_RETENTION_DAYS, -1)
        if (keepDays < 1) return

        val today = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            LocalDate.now()
        } else {
            try {
                LocalDate.parse(currentDayKey(), DateTimeFormatter.ISO_LOCAL_DATE)
            } catch (_: Exception) {
                return
            }
        }

        val cutoff = today.minusDays((keepDays - 1).toLong())
        if (keepDays < 1) return

        val editor = prefs.edit()
        var removed = 0

        for (k in prefs.all.keys) {
            when {
                k.startsWith(KEY_DAY_TOTAL_PREFIX) -> {
                    val dateStr = k.removePrefix(KEY_DAY_TOTAL_PREFIX)
                    val d = parseDateOrNull(dateStr)
                    if (d != null && d.isBefore(cutoff)) {
                        editor.remove(k)
                        removed++
                    }
                }
                k.startsWith(KEY_DAY_HOURLY_PREFIX) -> {
                    val rest = k.removePrefix(KEY_DAY_HOURLY_PREFIX)
                    val parts = rest.split("_")
                    if (parts.isNotEmpty()) {
                        val d = parseDateOrNull(parts[0])
                        if (d != null && d.isBefore(cutoff)) {
                            editor.remove(k)
                            removed++
                        }
                    }
                }
                k.startsWith(KEY_GOAL_ACHIEVED_PREFIX) -> {
                    val dateStr = k.removePrefix(KEY_GOAL_ACHIEVED_PREFIX)
                    val d = parseDateOrNull(dateStr)
                    if (d != null && d.isBefore(cutoff)) {
                        editor.remove(k)
                        removed++
                    }
                }
            }
        }

        editor.putLong(KEY_RETENTION_LAST_CLEANUP, System.currentTimeMillis())
        editor.apply()

        Log.i(TAG, "Retention cleanup done: keepDays=$keepDays cutoff=$cutoff removedKeys=$removed")
    }

    private fun parseDateOrNull(dateStr: String): LocalDate? {
        return try {
            LocalDate.parse(dateStr, DateTimeFormatter.ISO_LOCAL_DATE)
        } catch (_: Exception) {
            null
        }
    }


    override fun onCreate() {
        super.onCreate()

        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        runRetentionCleanupIfNeeded()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        createNotificationChannel()
        if (isTrackingEnabled()) {
            registerStepListener()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!hasActivityRecognitionPermission()) {
            Log.w(TAG, "No ACTIVITY_RECOGNITION permission, stopping service")
            stopSelf()
            return START_NOT_STICKY
        }

        if (!isTrackingEnabled()) {
            Log.i(TAG, "Tracking disabled flag set, stopping service")
            stopSelf()
            return START_NOT_STICKY
        }

        runRetentionCleanupIfNeeded()

        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        registerStepListener()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager.unregisterListener(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun hasActivityRecognitionPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun registerStepListener() {
        if (stepCounterSensor == null) {
            Log.w(TAG, "Step counter sensor not available on this device")
            return
        }

        if (!hasActivityRecognitionPermission()) {
            Log.w(TAG, "No ACTIVITY_RECOGNITION permission, not registering listener")
            return
        }

        sensorManager.registerListener(
            this,
            stepCounterSensor,
            SensorManager.SENSOR_DELAY_NORMAL,
        )
    }

    private fun currentDayKey(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        } else {
            val cal = Calendar.getInstance()
            "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH) + 1}-${cal.get(Calendar.DAY_OF_MONTH)}"
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type != Sensor.TYPE_STEP_COUNTER) return

        val rawValue = event.values.firstOrNull() ?: return
        val editor = prefs.edit()

        val lastRaw = prefs.getFloat(KEY_LAST_SENSOR_VALUE, -1f)

        if (lastRaw < 0f) {
            editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
            editor.apply()
            return
        }

        val delta = rawValue - lastRaw

        if (delta <= 0f || delta >= 50000f) {
            editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
            editor.apply()
            return
        }

        val deltaInt = delta.toInt()

        val dateKey = currentDayKey()
        val totalKey = "$KEY_DAY_TOTAL_PREFIX$dateKey"

        val currentTotal = prefs.getInt(totalKey, 0)
        val newTotal = currentTotal + deltaInt
        editor.putInt(totalKey, newTotal)

        val cal = Calendar.getInstance()
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val hourKey = "${KEY_DAY_HOURLY_PREFIX}${dateKey}_$hour"
        val hourValue = prefs.getInt(hourKey, 0)
        editor.putInt(hourKey, hourValue + deltaInt)

        editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
        editor.apply()

        checkAndNotifyGoalReached(newTotal)

        val broadcast = Intent(ACTION_STEPS_UPDATED)
        broadcast.putExtra(EXTRA_TODAY_STEPS, newTotal)
        sendBroadcast(broadcast)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Śledzenie kroków",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Zliczanie kroków w tle"
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Step Counter")
            .setContentText("Śledzenie kroków w tle jest włączone")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
