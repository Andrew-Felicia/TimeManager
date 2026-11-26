package app.flowtime.android.alarm

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.flowtime.android.FlowtimeApplication
import app.flowtime.android.MainActivity
import app.flowtime.android.R
import app.flowtime.android.data.TimerEndAlert
import java.util.Locale
import kotlin.math.max

class TimerAlarmService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var deadlineMillis = 0L
    private var title = "Focus timer"
    private var alert = TimerEndAlert.CLASSIC
    private var scheduledDurationSeconds = 0
    private var ringing = false
    private var toneGenerator: ToneGenerator? = null

    private val deadlineRunnable = Runnable { beginAlarm() }
    private val notificationUpdateRunnable = object : Runnable {
        override fun run() {
            if (ringing || deadlineMillis <= System.currentTimeMillis()) return
            val notificationsAllowed = Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(
                    this@TimerAlarmService,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            if (notificationsAllowed) {
                NotificationManagerCompat.from(this@TimerAlarmService)
                    .notify(NOTIFICATION_ID, runningNotification())
            }
            val delayToNextSecond = 1_000L - (System.currentTimeMillis() % 1_000L)
            handler.postDelayed(this, delayToNextSecond)
        }
    }
    private val toneRunnable = object : Runnable {
        override fun run() {
            if (!ringing) return
            val (tone, length, pause) = when (alert) {
                TimerEndAlert.CLASSIC -> Triple(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 850, 1_100L)
                TimerEndAlert.TWS -> Triple(ToneGenerator.TONE_PROP_BEEP2, 170, 420L)
                TimerEndAlert.MASTER_CAUTION -> Triple(ToneGenerator.TONE_CDMA_ABBR_ALERT, 500, 700L)
                TimerEndAlert.MISSILE_LAUNCH -> Triple(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 800, 850L)
                TimerEndAlert.RWR -> Triple(ToneGenerator.TONE_CDMA_NETWORK_BUSY, 300, 480L)
            }
            toneGenerator?.startTone(tone, length)
            handler.postDelayed(this, pause)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopAlarmAndSelf()
            ACTION_SCHEDULE -> {
                deadlineMillis = intent.getLongExtra(EXTRA_DEADLINE, System.currentTimeMillis())
                title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "Focus timer" }
                alert = TimerEndAlert.from(intent.getStringExtra(EXTRA_ALERT))
                scheduledDurationSeconds = intent.getIntExtra(EXTRA_DURATION_SECONDS, 0).coerceAtLeast(1)
                ringing = false
                stopSound()
                handler.removeCallbacks(deadlineRunnable)
                handler.removeCallbacks(notificationUpdateRunnable)
                startForeground(NOTIFICATION_ID, runningNotification())
                handler.postDelayed(notificationUpdateRunnable, 1_000L)
                val delay = max(0L, deadlineMillis - System.currentTimeMillis())
                if (delay == 0L) beginAlarm() else handler.postDelayed(deadlineRunnable, delay)
            }
        }
        return START_NOT_STICKY
    }

    private fun runningNotification(): Notification {
        val remainingSeconds = ((deadlineMillis - System.currentTimeMillis() + 999L) / 1_000L)
            .toInt()
            .coerceAtLeast(0)
        val totalSeconds = scheduledDurationSeconds.coerceAtLeast(remainingSeconds).coerceAtLeast(1)
        val elapsedSeconds = (totalSeconds - remainingSeconds).coerceIn(0, totalSeconds)

        return NotificationCompat.Builder(this, FlowtimeApplication.TIMER_CHANNEL)
            .setSmallIcon(R.drawable.ic_timer_notification)
            .setContentTitle("Timer running  ·  ${formattedCountdown(remainingSeconds)}")
            .setContentText(title)
            .setContentIntent(openAppIntent(stopAlarm = false))
            .setShowWhen(false)
            .setProgress(totalSeconds, elapsedSeconds, false)
            .setColor(0xFF4F8CFF.toInt())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun formattedCountdown(seconds: Int): String = if (seconds >= 3_600) {
        String.format(Locale.US, "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    } else {
        String.format(Locale.US, "%02d:%02d", seconds / 60, seconds % 60)
    }

    private fun beginAlarm() {
        if (ringing) return
        ringing = true
        handler.removeCallbacks(notificationUpdateRunnable)
        startForeground(NOTIFICATION_ID, alarmNotification())
        toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        vibrate()
        handler.post(toneRunnable)
    }

    private fun alarmNotification(): Notification = NotificationCompat.Builder(this, FlowtimeApplication.ALARM_CHANNEL)
        .setSmallIcon(R.drawable.ic_timer_notification)
        .setContentTitle("Timer finished")
        .setContentText("$title · Tap to stop")
        .setContentIntent(openAppIntent(stopAlarm = true))
        .setOngoing(true)
        .setAutoCancel(false)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setCategory(NotificationCompat.CATEGORY_ALARM)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .build()

    private fun openAppIntent(stopAlarm: Boolean): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_STOP_ALARM, stopAlarm)
        }
        return PendingIntent.getActivity(
            this,
            if (stopAlarm) 2 else 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun vibrate() {
        val pattern = when (alert) {
            TimerEndAlert.CLASSIC -> longArrayOf(0, 500, 350, 500, 900)
            TimerEndAlert.TWS -> longArrayOf(0, 120, 120, 120, 650)
            TimerEndAlert.MASTER_CAUTION -> longArrayOf(0, 230, 100, 230, 100, 230, 100, 230, 800)
            TimerEndAlert.MISSILE_LAUNCH -> longArrayOf(0, 700, 180, 700, 300)
            TimerEndAlert.RWR -> longArrayOf(0, 180, 120, 180, 120, 180, 500)
        }
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
    }

    private fun stopSound() {
        handler.removeCallbacks(toneRunnable)
        toneGenerator?.stopTone()
        toneGenerator?.release()
        toneGenerator = null
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        vibrator.cancel()
    }

    private fun stopAlarmAndSelf() {
        ringing = false
        handler.removeCallbacks(deadlineRunnable)
        handler.removeCallbacks(notificationUpdateRunnable)
        stopSound()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(deadlineRunnable)
        handler.removeCallbacks(notificationUpdateRunnable)
        stopSound()
        super.onDestroy()
    }

    companion object {
        private const val ACTION_SCHEDULE = "app.flowtime.android.SCHEDULE_TIMER"
        private const val ACTION_STOP = "app.flowtime.android.STOP_TIMER"
        private const val EXTRA_DEADLINE = "deadline"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ALERT = "alert"
        private const val EXTRA_DURATION_SECONDS = "durationSeconds"
        private const val NOTIFICATION_ID = 4101

        fun scheduleIntent(
            context: Context,
            deadline: Long,
            title: String,
            alert: TimerEndAlert,
            durationSeconds: Int
        ) =
            Intent(context, TimerAlarmService::class.java).apply {
                action = ACTION_SCHEDULE
                putExtra(EXTRA_DEADLINE, deadline)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_ALERT, alert.storedName)
                putExtra(EXTRA_DURATION_SECONDS, durationSeconds)
            }

        fun stopIntent(context: Context) = Intent(context, TimerAlarmService::class.java).apply {
            action = ACTION_STOP
        }
    }
}
