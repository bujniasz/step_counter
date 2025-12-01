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
        private const val CHANNEL_ID = "step_tracking_channel"
        private const val NOTIFICATION_ID = 1

        private const val PREFS_NAME = "step_counter_prefs"

        // Surowa wartość z TYPE_STEP_COUNTER z ostatniego zdarzenia
        private const val KEY_LAST_SENSOR_VALUE = "last_sensor_value"

        // Historia: suma kroków i biny godzinowe dla każdej daty
        private const val KEY_DAY_TOTAL_PREFIX = "day_total_"      // + dateKey
        private const val KEY_DAY_HOURLY_PREFIX = "day_hour_"      // + dateKey + "_<hour>"

        const val ACTION_STEPS_UPDATED =
            "com.example.step_counter.STEPS_UPDATED"
        const val EXTRA_TODAY_STEPS = "extra_today_steps"
    }

    private lateinit var sensorManager: SensorManager
    private var stepCounterSensor: Sensor? = null
    private lateinit var prefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()

        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        createNotificationChannel()
        registerStepListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
        // ignored
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type != Sensor.TYPE_STEP_COUNTER) return

        val rawValue = event.values.firstOrNull() ?: return
        val editor = prefs.edit()

        val lastRaw = prefs.getFloat(KEY_LAST_SENSOR_VALUE, -1f)

        if (lastRaw < 0f) {
            // Pierwsze znane zdarzenie – ustaw bazę i nic nie dodawaj
            editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
            editor.apply()
            return
        }

        val delta = rawValue - lastRaw

        // sanity-check
        if (delta <= 0f || delta >= 50000f) {
            editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
            editor.apply()
            return
        }

        val deltaInt = delta.toInt()

        val dateKey = currentDayKey()
        val totalKey = "$KEY_DAY_TOTAL_PREFIX$dateKey"

        // Zaktualizuj sumę dla bieżącego dnia
        val currentTotal = prefs.getInt(totalKey, 0)
        val newTotal = currentTotal + deltaInt
        editor.putInt(totalKey, newTotal)

        // Zaktualizuj bin godzinowy (0–23) dla bieżącego dnia
        val cal = Calendar.getInstance()
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val hourKey = "${KEY_DAY_HOURLY_PREFIX}${dateKey}_$hour"
        val hourValue = prefs.getInt(hourKey, 0)
        editor.putInt(hourKey, hourValue + deltaInt)

        // Zaktualizuj surową wartość sensora
        editor.putFloat(KEY_LAST_SENSOR_VALUE, rawValue)
        editor.apply()

        // Powiadom Flutter o nowej liczbie kroków dla dzisiaj
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
