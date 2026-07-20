package com.perpova.staf_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

class StaffShiftWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE_SHIFT = "com.perpova.staf_app.ACTION_TOGGLE_SHIFT"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetUI(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE_SHIFT) {
            handleBackgroundToggle(context)
        }
    }

    private fun updateWidgetUI(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val hwPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val flPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val status = hwPrefs.getString("widget_status", null)
            ?: flPrefs.getString("flutter.widget_status", null)
            ?: flPrefs.getString("widget_status", "CLOCKED OUT")
            ?: "CLOCKED OUT"

        val time = hwPrefs.getString("widget_time", null)
            ?: flPrefs.getString("flutter.widget_time", null)
            ?: flPrefs.getString("widget_time", "Ready for shift")
            ?: "Ready for shift"

        val button = hwPrefs.getString("widget_button", null)
            ?: flPrefs.getString("flutter.widget_button", null)
            ?: flPrefs.getString("widget_button", "CLOCK IN")
            ?: "CLOCK IN"

        // Silent broadcast PendingIntent — does NOT open app
        val toggleIntent = Intent(context, StaffShiftWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_SHIFT
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val views = RemoteViews(context.packageName, R.layout.staff_shift_widget).apply {
            setTextViewText(R.id.widget_status, status)
            setTextViewText(R.id.widget_time, time)
            setTextViewText(R.id.widget_button, button)

            setOnClickPendingIntent(R.id.widget_button, pendingIntent)
            setOnClickPendingIntent(R.id.widget_container, pendingIntent)
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun handleBackgroundToggle(context: Context) {
        thread {
            try {
                val hwPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                val flPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                val token = flPrefs.getString("flutter.auth_token", null)
                var baseUrl = flPrefs.getString("flutter.api_base_url", "http://192.168.1.100:3000") ?: "http://192.168.1.100:3000"
                if (!baseUrl.startsWith("http://") && !baseUrl.startsWith("https://")) {
                    baseUrl = "http://$baseUrl"
                }
                baseUrl = baseUrl.trimEnd('/')

                var isIn = hwPrefs.getBoolean("widget_is_in", false)
                if (!hwPrefs.contains("widget_is_in")) {
                    if (flPrefs.contains("flutter.widget_is_in")) {
                        isIn = flPrefs.getBoolean("flutter.widget_is_in", false)
                    } else if (flPrefs.contains("widget_is_in")) {
                        isIn = flPrefs.getBoolean("widget_is_in", false)
                    }
                }

                val endpoint = if (isIn) "$baseUrl/api/staff/clock-out" else "$baseUrl/api/staff/clock-in"

                val url = URL(endpoint)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                if (!token.isNullOrEmpty()) {
                    conn.setRequestProperty("Authorization", "Bearer $token")
                }
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                conn.doOutput = true

                val os = OutputStreamWriter(conn.outputStream)
                os.write("{}")
                os.flush()
                os.close()

                val responseCode = conn.responseCode
                if (responseCode == 200) {
                    val newIsIn = !isIn
                    val nowTime = SimpleDateFormat("hh:mm a", Locale.getDefault()).format(Date())
                    val newStatus = if (newIsIn) "CLOCKED IN" else "CLOCKED OUT"
                    val newTime = if (newIsIn) "Since $nowTime" else "Ready for shift"
                    val newButton = if (newIsIn) "CLOCK OUT" else "CLOCK IN"

                    hwPrefs.edit()
                        .putString("widget_status", newStatus)
                        .putString("widget_time", newTime)
                        .putString("widget_button", newButton)
                        .putBoolean("widget_is_in", newIsIn)
                        .apply()

                    flPrefs.edit()
                        .putString("flutter.widget_status", newStatus)
                        .putString("flutter.widget_time", newTime)
                        .putString("flutter.widget_button", newButton)
                        .putBoolean("flutter.widget_is_in", newIsIn)
                        .putString("widget_status", newStatus)
                        .putString("widget_time", newTime)
                        .putString("widget_button", newButton)
                        .putBoolean("widget_is_in", newIsIn)
                        .apply()

                    // Instantly update widget UI on home screen
                    val appWidgetManager = AppWidgetManager.getInstance(context)
                    val componentName = ComponentName(context, StaffShiftWidgetProvider::class.java)
                    val ids = appWidgetManager.getAppWidgetIds(componentName)
                    for (id in ids) {
                        updateWidgetUI(context, appWidgetManager, id)
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
