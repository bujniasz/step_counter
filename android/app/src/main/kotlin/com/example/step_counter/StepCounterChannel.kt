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
import org.json.JSONArray
import org.json.JSONObject
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
        private const val KEY_GOAL_LAST_NOTIFIED_DATE = "goal_last_notified_date"

        // Runtime-only state from sensor (do NOT export/import)
        private const val KEY_LAST_SENSOR_VALUE = "last_sensor_value"

        private const val EXPORT_SCHEMA = "step_counter_export"
        private const val EXPORT_SCHEMA_VERSION = 1

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

    private fun prefValueToJson(value: Any?): Any {
        return when (value) {
            null -> JSONObject.NULL
            is Boolean, is Int, is Long, is Double, is Float, is String -> value
            is Set<*> -> {
                val arr = JSONArray()
                value.filterIsInstance<String>().forEach { arr.put(it) }
                arr
            }
            else -> value.toString()
        }
    }

    private fun exportAllDataAsJson(): String {
        val root = JSONObject()
        root.put("schema", EXPORT_SCHEMA)
        root.put("schema_version", EXPORT_SCHEMA_VERSION)
        root.put("exported_at", java.time.Instant.now().toString())

        val app = JSONObject()
        app.put("platform", "android")
        app.put("package", context.packageName)
        root.put("app", app)

        val data = JSONObject()

        // Days
        val days = JSONObject()
        val all = prefs.all
        val dayKeys = all.keys
            .filter { it.startsWith(KEY_DAY_TOTAL_PREFIX) }
            .map { it.removePrefix(KEY_DAY_TOTAL_PREFIX) }
            .distinct()
            .sorted()

        for (dateKey in dayKeys) {
            val dayObj = JSONObject()
            dayObj.put("total", prefs.getInt("$KEY_DAY_TOTAL_PREFIX$dateKey", 0))

            val hourly = JSONArray()
            for (h in 0..23) {
                val v = prefs.getInt("${KEY_DAY_HOURLY_PREFIX}${dateKey}_$h", 0)
                hourly.put(v)
            }
            dayObj.put("hourly", hourly)

            val goalKey = "$KEY_GOAL_ACHIEVED_PREFIX$dateKey"
            if (prefs.contains(goalKey)) {
                dayObj.put("goal_achieved", prefs.getInt(goalKey, 0))
            } else {
                dayObj.put("goal_achieved", JSONObject.NULL)
            }

            days.put(dateKey, dayObj)
        }

        data.put("days", days)

        // Settings
        val settings = JSONObject()
        settings.put(KEY_DAILY_GOAL_STEPS, prefs.getInt(KEY_DAILY_GOAL_STEPS, 8000))
        settings.put(KEY_GOAL_NOTIFICATION_ENABLED, prefs.getBoolean(KEY_GOAL_NOTIFICATION_ENABLED, true))
        settings.put(StepTrackingService.KEY_TRACKING_ENABLED, prefs.getBoolean(StepTrackingService.KEY_TRACKING_ENABLED, true))
        data.put("settings", settings)

        // Meta
        val meta = JSONObject()
        val lastNotified = prefs.getString(KEY_GOAL_LAST_NOTIFIED_DATE, null)
        if (lastNotified != null) meta.put(KEY_GOAL_LAST_NOTIFIED_DATE, lastNotified) else meta.put(KEY_GOAL_LAST_NOTIFIED_DATE, JSONObject.NULL)
        data.put("meta", meta)

        // Extras (future-proof): export unknown keys except history + runtime-only
        val extras = JSONObject()
        val reservedPrefixes = listOf(KEY_DAY_TOTAL_PREFIX, KEY_DAY_HOURLY_PREFIX, KEY_GOAL_ACHIEVED_PREFIX)
        val reservedExact = setOf(
            KEY_DAILY_GOAL_STEPS,
            KEY_GOAL_NOTIFICATION_ENABLED,
            KEY_GOAL_LAST_NOTIFIED_DATE,
            StepTrackingService.KEY_TRACKING_ENABLED,
            KEY_LAST_SENSOR_VALUE,
        )

        for ((k, v) in all) {
            if (reservedExact.contains(k)) continue
            if (reservedPrefixes.any { k.startsWith(it) }) continue
            extras.put(k, prefValueToJson(v))
        }
        data.put("extras", extras)

        root.put("data", data)
        return root.toString(2)
    }

    private fun parseAndValidateExport(json: String): JSONObject {
        val root = JSONObject(json)
        val schema = root.optString("schema", "")
        if (schema != EXPORT_SCHEMA) {
            throw IllegalArgumentException("UNSUPPORTED_SCHEMA")
        }
        val version = root.optInt("schema_version", -1)
        if (version != EXPORT_SCHEMA_VERSION) {
            throw IllegalArgumentException("UNSUPPORTED_SCHEMA_VERSION")
        }
        val data = root.optJSONObject("data")
            ?: throw IllegalArgumentException("VALIDATION_FAILED: missing data")
        val days = data.optJSONObject("days")
            ?: throw IllegalArgumentException("VALIDATION_FAILED: missing days")
        // at least ensure it's an object
        return root
    }

    private fun previewImport(json: String): Map<String, Any?> {
        val root = parseAndValidateExport(json)
        val data = root.getJSONObject("data")
        val days = data.getJSONObject("days")

        val dayNames = days.keys().asSequence().toList()
        var existing = 0
        for (d in dayNames) {
            if (prefs.contains("$KEY_DAY_TOTAL_PREFIX$d")) existing++
        }
        val settingsInFile = data.optJSONObject("settings") != null
        return mapOf(
            "schema_version" to root.getInt("schema_version"),
            "days_in_file" to dayNames.size,
            "days_existing" to existing,
            "days_new" to (dayNames.size - existing),
            "settings_in_file" to settingsInFile,
        )
    }

    private enum class ImportMode {
        MERGE_SKIP,
        MERGE_OVERWRITE,
        REPLACE_ALL_HISTORY,
    }

    private fun importData(json: String, mode: ImportMode, importSettings: Boolean): Map<String, Any?> {
        val root = parseAndValidateExport(json)
        val data = root.getJSONObject("data")
        val days = data.getJSONObject("days")

        val editor = prefs.edit()

        if (mode == ImportMode.REPLACE_ALL_HISTORY) {
            for (k in prefs.all.keys) {
                if (k.startsWith(KEY_DAY_TOTAL_PREFIX) ||
                    k.startsWith(KEY_DAY_HOURLY_PREFIX) ||
                    k.startsWith(KEY_GOAL_ACHIEVED_PREFIX)
                ) {
                    editor.remove(k)
                }
            }
        }

        var importedDays = 0
        var skippedDays = 0
        var overwrittenDays = 0

        for (dateKey in days.keys()) {
            val dayObj = days.optJSONObject(dateKey)
                ?: continue

            val total = dayObj.optInt("total", 0)
            val hourlyArr = dayObj.optJSONArray("hourly") ?: JSONArray()
            if (hourlyArr.length() != 24) {
                throw IllegalArgumentException("VALIDATION_FAILED: hourly must have 24 values for $dateKey")
            }

            val exists = prefs.contains("$KEY_DAY_TOTAL_PREFIX$dateKey")
            if (exists && mode == ImportMode.MERGE_SKIP) {
                skippedDays++
                continue
            }
            if (exists && mode == ImportMode.MERGE_OVERWRITE) {
                overwrittenDays++
            }

            editor.putInt("$KEY_DAY_TOTAL_PREFIX$dateKey", total)
            for (h in 0..23) {
                editor.putInt("${KEY_DAY_HOURLY_PREFIX}${dateKey}_$h", hourlyArr.optInt(h, 0))
            }

            val goalKey = "$KEY_GOAL_ACHIEVED_PREFIX$dateKey"
            if (dayObj.isNull("goal_achieved")) {
                editor.remove(goalKey)
            } else {
                val goal = dayObj.optInt("goal_achieved", 0)
                if (goal > 0) editor.putInt(goalKey, goal) else editor.remove(goalKey)
            }

            importedDays++
        }

        var importedSettings = false
        if (importSettings) {
            val settings = data.optJSONObject("settings")
            if (settings != null) {
                if (settings.has(KEY_DAILY_GOAL_STEPS)) {
                    editor.putInt(KEY_DAILY_GOAL_STEPS, settings.optInt(KEY_DAILY_GOAL_STEPS, 8000))
                }
                if (settings.has(KEY_GOAL_NOTIFICATION_ENABLED)) {
                    editor.putBoolean(KEY_GOAL_NOTIFICATION_ENABLED, settings.optBoolean(KEY_GOAL_NOTIFICATION_ENABLED, true))
                }
                if (settings.has(StepTrackingService.KEY_TRACKING_ENABLED)) {
                    editor.putBoolean(StepTrackingService.KEY_TRACKING_ENABLED, settings.optBoolean(StepTrackingService.KEY_TRACKING_ENABLED, true))
                }
                importedSettings = true
            }

            val meta = data.optJSONObject("meta")
            if (meta != null && meta.has(KEY_GOAL_LAST_NOTIFIED_DATE)) {
                if (meta.isNull(KEY_GOAL_LAST_NOTIFIED_DATE)) {
                    editor.remove(KEY_GOAL_LAST_NOTIFIED_DATE)
                } else {
                    editor.putString(KEY_GOAL_LAST_NOTIFIED_DATE, meta.optString(KEY_GOAL_LAST_NOTIFIED_DATE, null))
                }
            }

            // Optionally restore extras too
            val extras = data.optJSONObject("extras")
            if (extras != null) {
                for (k in extras.keys()) {
                    val v = extras.get(k)
                    when (v) {
                        is Boolean -> editor.putBoolean(k, v)
                        is Int -> editor.putInt(k, v)
                        is Long -> editor.putLong(k, v)
                        is Double -> editor.putFloat(k, v.toFloat())
                        is String -> editor.putString(k, v)
                        JSONObject.NULL -> editor.remove(k)
                        else -> editor.putString(k, v.toString())
                    }
                }
            }
        }

        editor.apply()

        return mapOf(
            "imported_days" to importedDays,
            "skipped_days" to skippedDays,
            "overwritten_days" to overwrittenDays,
            "imported_settings" to importedSettings,
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportData" -> {
                try {
                    result.success(exportAllDataAsJson())
                } catch (e: Exception) {
                    result.error("EXPORT_FAILED", e.message, null)
                }
            }
            "previewImport" -> {
                val json = call.arguments as? String
                if (json == null) {
                    result.error("ARG_ERROR", "json is null", null)
                    return
                }
                try {
                    result.success(previewImport(json))
                } catch (e: IllegalArgumentException) {
                    val msg = e.message ?: "INVALID"
                    val code = when {
                        msg.startsWith("UNSUPPORTED_SCHEMA") -> "UNSUPPORTED_SCHEMA"
                        msg.startsWith("UNSUPPORTED_SCHEMA_VERSION") -> "UNSUPPORTED_SCHEMA_VERSION"
                        msg.startsWith("VALIDATION_FAILED") -> "VALIDATION_FAILED"
                        else -> "INVALID_JSON"
                    }
                    result.error(code, msg, null)
                } catch (e: Exception) {
                    result.error("PREVIEW_FAILED", e.message, null)
                }
            }
            "importData" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("ARG_ERROR", "args is null", null)
                    return
                }
                val json = args["json"] as? String
                val modeRaw = args["mode"] as? String
                val importSettings = args["importSettings"] as? Boolean ?: true
                if (json == null || modeRaw == null) {
                    result.error("ARG_ERROR", "json/mode is null", null)
                    return
                }
                val mode = try {
                    ImportMode.valueOf(modeRaw)
                } catch (e: Exception) {
                    result.error("ARG_ERROR", "unknown mode: $modeRaw", null)
                    return
                }
                try {
                    result.success(importData(json, mode, importSettings))
                } catch (e: IllegalArgumentException) {
                    val msg = e.message ?: "INVALID"
                    val code = when {
                        msg.startsWith("UNSUPPORTED_SCHEMA") -> "UNSUPPORTED_SCHEMA"
                        msg.startsWith("UNSUPPORTED_SCHEMA_VERSION") -> "UNSUPPORTED_SCHEMA_VERSION"
                        msg.startsWith("VALIDATION_FAILED") -> "VALIDATION_FAILED"
                        else -> "INVALID_JSON"
                    }
                    result.error(code, msg, null)
                } catch (e: Exception) {
                    result.error("IMPORT_FAILED", e.message, null)
                }
            }
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
