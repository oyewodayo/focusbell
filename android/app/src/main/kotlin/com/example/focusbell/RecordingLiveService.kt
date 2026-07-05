package co.ibeep.focusbell

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RecordingLiveService : Service() {

    companion object {
        const val CHANNEL_ID = "focusbell_recording_live"
        const val NOTIF_ID = 5011
        const val ACTION_START = "co.ibeep.focusbell.action.START_RECORDING"
        const val ACTION_STOP = "co.ibeep.focusbell.action.STOP_RECORDING"
        const val EXTRA_TITLE = "extra_title"
    }

    private var startTimeMillis: Long = 0L

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Voice note"
                startTimeMillis = System.currentTimeMillis()
                val notification = buildNotification(title)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                } else {
                    startForeground(NOTIF_ID, notification)
                }
            }
        }
        return START_STICKY
    }

    private fun buildNotification(title: String): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_audio_online)
            .setContentTitle("Recording · $title")
            .setContentText("Tap to return to FocusBell")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(startTimeMillis)
            .setUsesChronometer(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        try {
            builder.javaClass
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                .invoke(builder, true)
        } catch (_: Exception) {  
            android.util.Log.d("RecordingLiveService", "Promoted ongoing NOT available: ${e.message}")
        }

        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Voice recording", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Shown while FocusBell is recording a voice note" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}