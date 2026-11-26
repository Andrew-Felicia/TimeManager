package app.flowtime.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes

class FlowtimeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                TIMER_CHANNEL,
                "Running timers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows a focus timer while it is running"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                ALARM_CHANNEL,
                "Timer alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts you when a Flowtime timer finishes"
                setSound(null, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
    }

    companion object {
        const val TIMER_CHANNEL = "flowtime.timer.running"
        const val ALARM_CHANNEL = "flowtime.timer.alarm"
    }
}
