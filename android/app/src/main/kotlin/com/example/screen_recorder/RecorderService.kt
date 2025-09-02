package com.example.screen_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RecorderService : Service() {
    companion object {
        const val CHANNEL_ID = "screen_recorder_channel"
        const val NOTIF_ID = 101
        const val ACTION_START = "com.example.screen_recorder.ACTION_START"
        const val ACTION_STOP = "com.example.screen_recorder.ACTION_STOP"
        const val ACTION_PAUSE = "com.example.screen_recorder.ACTION_PAUSE"
        const val ACTION_RESUME = "com.example.screen_recorder.ACTION_RESUME"
    }

    private var isRecording: Boolean = false
    private var isPaused: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart()
            ACTION_STOP -> handleStop()
            ACTION_PAUSE -> handlePause()
            ACTION_RESUME -> handleResume()
            else -> {
                // If started without explicit action, ensure a foreground notification exists
                if (!isRecording) {
                    val notif = buildNotification()
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.notify(NOTIF_ID, notif)
                }
            }
        }
        return START_STICKY
    }

    private fun handleStart() {
        if (isRecording) return
        isRecording = true
        isPaused = false
        val notif = buildNotification()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, notif)
        // TODO: Start MediaProjection + MediaRecorder in future iteration.
    }

    private fun handlePause() {
        if (!isRecording || isPaused) return
        isPaused = true
        // TODO: Pause recording if supported.
        updateNotification()
    }

    private fun handleResume() {
        if (!isRecording || !isPaused) return
        isPaused = false
        // TODO: Resume recording.
        updateNotification()
    }

    private fun handleStop() {
        if (!isRecording) {
            stopSelf()
            return
        }
        isRecording = false
        isPaused = false
        // TODO: Stop and save recording.
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIF_ID)
        stopSelf()
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                createChannel()
            }
        }

        val title = if (isRecording) {
            if (isPaused) "Recording paused" else "Recording in progress"
        } else {
            "Screen Recorder"
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or legacyMutable()
        )

        val actions = mutableListOf<NotificationCompat.Action>()
        if (!isRecording) {
            actions += NotificationCompat.Action.Builder(0, "Start", pendingFor(ACTION_START)).build()
        } else {
            if (isPaused) {
                actions += NotificationCompat.Action.Builder(0, "Resume", pendingFor(ACTION_RESUME)).build()
            } else {
                actions += NotificationCompat.Action.Builder(0, "Pause", pendingFor(ACTION_PAUSE)).build()
            }
            actions += NotificationCompat.Action.Builder(0, "Stop", pendingFor(ACTION_STOP)).build()
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle(title)
            .setContentText("Control recording from here")
            .setContentIntent(contentIntent)
            .setOngoing(isRecording)
            .setOnlyAlertOnce(true)
            .setColor(Color.parseColor("#3F51B5"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        actions.forEach { builder.addAction(it) }
        return builder.build()
    }

    private fun pendingFor(action: String): PendingIntent {
        val intent = Intent(this, RecorderService::class.java).apply { this.action = action }
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or legacyMutable()
        )
    }

    private fun legacyMutable(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Recorder",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Ongoing screen recording"
                enableLights(false)
                enableVibration(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
