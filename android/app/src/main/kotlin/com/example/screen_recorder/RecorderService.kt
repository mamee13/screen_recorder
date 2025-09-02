package com.example.screen_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
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

    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: android.hardware.display.VirtualDisplay? = null
    private var outputUri: Uri? = null

    private var width: Int = 1080
    private var height: Int = 1920
    private var fps: Int = 30
    private var bitrateKbps: Int = 8000
    private var includeAudio: Boolean = true

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
            ACTION_PAUSE -> handlePause()
            ACTION_RESUME -> handleResume()
            else -> Unit
        }
        return START_STICKY
    }

    private fun handleStart(intent: Intent) {
        if (isRecording) return
        isRecording = true
        isPaused = false

        // Read settings
        width = intent.getIntExtra("width", width)
        height = intent.getIntExtra("height", height)
        fps = intent.getIntExtra("fps", fps)
        bitrateKbps = intent.getIntExtra("bitrateKbps", bitrateKbps)
        includeAudio = intent.getBooleanExtra("includeAudio", includeAudio)

        // Start as a Foreground Service with the correct type (Android 14+) BEFORE using MediaProjection
        val notif = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notif)
        }

        // Acquire MediaProjection
        val resultCode = intent.getIntExtra("resultCode", 0)
        val data: Intent? = intent.getParcelableExtra("data")
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data!!)

        try {
            prepareRecorder()
            startRecording()
        } catch (e: Exception) {
            Log.e("RecorderService", "Failed to start recording", e)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
    }

    private fun prepareRecorder() {
        // Create output in MediaStore so it appears in Gallery
        val fileName = "Screen_${System.currentTimeMillis()}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Screen Recorder")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val resolver = contentResolver
        outputUri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Failed to create MediaStore entry")

        mediaRecorder = MediaRecorder()
        if (includeAudio) {
            mediaRecorder?.setAudioSource(MediaRecorder.AudioSource.MIC)
        }
        mediaRecorder?.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mediaRecorder?.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder?.setOutputFile(resolver.openFileDescriptor(outputUri!!, "w")!!.fileDescriptor)
        mediaRecorder?.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        mediaRecorder?.setVideoEncodingBitRate(bitrateKbps * 1000)
        mediaRecorder?.setVideoFrameRate(fps)
        mediaRecorder?.setVideoSize(width, height)
        if (includeAudio) {
            mediaRecorder?.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder?.setAudioEncodingBitRate(128_000)
            mediaRecorder?.setAudioSamplingRate(44100)
        }
        mediaRecorder?.prepare()
    }

    private fun startRecording() {
        val metrics = resources.displayMetrics
        val densityDpi = metrics.densityDpi
        val surface: Surface = mediaRecorder!!.surface
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "screen_recorder",
            width,
            height,
            densityDpi,
            0,
            surface,
            null,
            null
        )
        mediaRecorder?.start()
        updateNotification()
    }

    private fun handlePause() {
        if (!isRecording || isPaused) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                mediaRecorder?.pause()
                isPaused = true
                updateNotification()
            } catch (e: Exception) {
                Log.w("RecorderService", "Pause not supported: ${e.message}")
            }
        }
    }

    private fun handleResume() {
        if (!isRecording || !isPaused) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                mediaRecorder?.resume()
                isPaused = false
                updateNotification()
            } catch (e: Exception) {
                Log.w("RecorderService", "Resume not supported: ${e.message}")
            }
        }
    }

    private fun handleStop() {
        if (!isRecording) {
            stopSelf()
            return
        }
        isRecording = false
        isPaused = false

        try {
            mediaRecorder?.apply {
                try { stop() } catch (_: Exception) {}
                reset()
                release()
            }
        } catch (_: Exception) {}
        mediaRecorder = null

        try {
            virtualDisplay?.release()
        } catch (_: Exception) {}
        virtualDisplay = null

        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null

        // Mark file as complete in MediaStore
        outputUri?.let { uri ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val cv = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
                contentResolver.update(uri, cv, null, null)
            }
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
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
            actions += NotificationCompat.Action.Builder(0, "Start", pendingStartActivity()).build()
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

    private fun pendingStartActivity(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra("start_from_notification", true)
        }
        return PendingIntent.getActivity(
            this,
            9991,
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
