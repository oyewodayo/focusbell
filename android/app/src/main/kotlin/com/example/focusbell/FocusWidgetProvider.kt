package com.example.focusbell

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class FocusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        val projectName   = prefs.getString("active_project_name", "No active project") ?: "No active project"
        val priorityDot   = prefs.getString("active_priority_dot", "⚪") ?: "⚪"
        val priorityLabel = prefs.getString("active_priority_label", "") ?: ""
        val timerText     = prefs.getString("session_timer_text", "⏱ No active session") ?: "⏱ No active session"
        val taskSummary   = prefs.getString("task_summary", "") ?: ""
        val sessionRunning = prefs.getInt("session_running", 0) == 1

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_widget_small)

            views.setTextViewText(R.id.widget_priority_dot,   priorityDot)
            views.setTextViewText(R.id.widget_project_name,   projectName)
            views.setTextViewText(R.id.widget_priority_label, priorityLabel)
            views.setTextViewText(R.id.widget_timer,          timerText)
            views.setTextViewText(R.id.widget_task_summary,   taskSummary)

            // Tapping anywhere on the widget opens the app
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}