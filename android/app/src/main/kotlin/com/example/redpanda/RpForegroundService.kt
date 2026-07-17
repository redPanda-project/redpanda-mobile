package com.example.redpanda

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app process — and with it the Dart
 * network isolate holding the TCP connections to the mailbox nodes — alive
 * while the activity is backgrounded or the screen is off (T16). Without it
 * Android (MIUI especially) freezes the process within seconds and message
 * reception stops until the app is reopened.
 *
 * The service carries no logic of its own: it is only a lifecycle anchor
 * with the mandatory persistent notification. If the process is killed
 * anyway (swipe-away, OOM), the Flutter engine is gone and a bare service
 * restart could not receive messages — so the service stops itself instead
 * of lingering as a zombie notification (see [onTaskRemoved]).
 *
 * Type is `specialUse` (peer-to-peer messenger without push infrastructure):
 * `dataSync` is time-boxed to 6 h per day from Android 15, which would
 * silently stop reception mid-day.
 */
class RpForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Background reception",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps the connection to your mailbox node alive"
                    setShowBadge(false)
                }
            )
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Listening for messages")
            .setContentText("RedPanda stays connected in the background")
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // NOT_STICKY: after a process death the Flutter engine is gone, so a
        // system-restarted service could not receive anything — it would
        // only resurrect the notification as a zombie.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The user swiped the app away: the Flutter engine dies with the
        // task, so a surviving service could not receive anything anyway.
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "rp_foreground_reception"
        private const val NOTIFICATION_ID = 1
    }
}
