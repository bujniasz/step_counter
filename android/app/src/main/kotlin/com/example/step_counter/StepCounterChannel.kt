package com.example.step_counter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar

class StepCounterChannel(
    private val context: Context,
    binaryMessenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME = "step_counter/methods"
        private const val EVENT_CHANNEL_NAME = "step_counter/events"

        private const val PREFS_NAME = "step_counter_prefs"

        private const val KEY_DAY_TOTAL_PREFIX = "day_total_"      // + dateKey
        private const val KEY_DAY_HOURLY_PREFIX = "day_hour_"      // + dateKey + "_<hour>"

        private const val KEY_DAILY_GOAL_STEPS = "daily_goal_steps"
        private const val KEY_GOAL_NOTIFICATION_ENABLED = "goal_notification_enabled"

        private const val KEY_GOAL_ACHIEVED_PREFIX = "goal_achieved_"
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(StepTrackingService.PREFS_NAME, Context.MODE_PRIVATE)

    private fun setDailyGoal(steps: Int) {
        prefs.edit()
            .putInt(KEY_DAILY_GOAL_STEPS, steps)
            .apply()
    }

    private fun isGoalNotificationEnabled(): Boolean {
        return prefs.getBoolean(KEY_GOAL_NOTIFICATION_ENABLED, true)
    }

    private fun setGoalNotificationEnabled(enabled: Boolean) {
        prefs.edit()
            .putBoolean(KEY_GOAL_NOTIFICATION_ENABLED, enabled)
            .apply()
    }

    private val methodChannel =
        MethodChannel(binaryMessenger, METHOD_CHANNEL_NAME)
    private val eventChannel =
        EventChannel(binaryMessenger, EVENT_CHANNEL_NAME)

    private var eventSink: EventChannel.EventSink? = null

    private val stepsReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action == StepTrackingService.ACTION_STEPS_UPDATED) {
                val steps = intent.getIntExtra(
                    StepTrackingService.EXTRA_TODAY_STEPS,
                    getTodayStepsInternal()
                )
                eventSink?.success(steps)
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                events.success(getTodayStepsInternal())
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        val filter = IntentFilter(StepTrackingService.ACTION_STEPS_UPDATED)
        context.registerReceiver(stepsReceiver, filter)
    }

    private fun isTrackingEnabled(): Boolean {
        return prefs.getBoolean(StepTrackingService.KEY_TRACKING_ENABLED, true)
    }

    private fun showTrackingDisabledNotification() {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                StepTrackingService.CHANNEL_ID,
                "Śledzenie kroków",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Zliczanie kroków w tle"
            }
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, StepTrackingService.CHANNEL_ID)
            .setContentTitle("Step Counter")
            .setContentText("Śledzenie kroków w tle jest wyłączone")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(false)
            .setAutoCancel(true)
            .build()

        manager.notify(2, notification)
    }

    private fun currentDayKey(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
        } else {
            val cal = Calendar.getInstance()
            "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH) + 1}-${cal.get(Calendar.DAY_OF_MONTH)}"
        }
    }

    private fun getTodayStepsInternal(): Int {
        val todayKey = currentDayKey()
        return prefs.getInt("$KEY_DAY_TOTAL_PREFIX$todayKey", 0)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isTrackingEnabled" -> {
                result.success(isTrackingEnabled())
            }
            "setDailyGoal" -> {
                val steps = call.arguments as? Int
                if (steps == null) {
                    result.error("ARG_ERROR", "steps is null", null)
                    return
                }
                setDailyGoal(steps)
                result.success(null)
            }
            "isGoalNotificationEnabled" -> {
                result.success(isGoalNotificationEnabled())
            }
            "setGoalNotificationEnabled" -> {
                val enabled = call.arguments as? Boolean
                if (enabled == null) {
                    result.error("ARG_ERROR", "enabled is null", null)
                    return
                }
                setGoalNotificationEnabled(enabled)
                result.success(null)
            }
            "getAchievedGoalForDate" -> {
                val dateKey = call.arguments as? String
                if (dateKey == null) {
                    result.error("ARG_ERROR", "dateKey is null", null)
                    return
                }
                val key = "$KEY_GOAL_ACHIEVED_PREFIX$dateKey"
                if (!prefs.contains(key)) {
                    result.success(null)
                } else {
                    result.success(prefs.getInt(key, 0))
                }
            }
            "getTodaySteps" -> {
                result.success(getTodayStepsInternal())
            }
            "getTodayHourlySteps" -> {
                val todayKey = currentDayKey()
                val list = ArrayList<Int>(24)
                for (h in 0..23) {
                    list.add(
                        prefs.getInt(
                            "${KEY_DAY_HOURLY_PREFIX}${todayKey}_$h",
                            0
                        )
                    )
                }
                result.success(list)
            }

            "getStepsForDate" -> {
                val dateKey = call.arguments as? String
                if (dateKey == null) {
                    result.error("ARG_ERROR", "dateKey is null", null)
                    return
                }
                val total = prefs.getInt("$KEY_DAY_TOTAL_PREFIX$dateKey", 0)
                result.success(total)
            }
            "getHourlyStepsForDate" -> {
                val dateKey = call.arguments as? String
                if (dateKey == null) {
                    result.error("ARG_ERROR", "dateKey is null", null)
                    return
                }
                val list = ArrayList<Int>(24)
                for (h in 0..23) {
                    list.add(
                        prefs.getInt(
                            "${KEY_DAY_HOURLY_PREFIX}${dateKey}_$h",
                            0
                        )
                    )
                }
                result.success(list)
            }

            "startTrackingService" -> {
                try {
                    // Flaga ON
                    prefs.edit()
                        .putBoolean(StepTrackingService.KEY_TRACKING_ENABLED, true)
                        .apply()

                    val manager =
                        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.cancel(2)

                    val intent = Intent(context, StepTrackingService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message, null)
                }
            }
            "stopTrackingService" -> {
                try {
                    prefs.edit()
                        .putBoolean(StepTrackingService.KEY_TRACKING_ENABLED, false)
                        .apply()

                    // Zatrzymaj serwis
                    val intent = Intent(context, StepTrackingService::class.java)
                    context.stopService(intent)

                    showTrackingDisabledNotification()

                    result.success(null)
                } catch (e: Exception) {
                    result.error("STOP_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
