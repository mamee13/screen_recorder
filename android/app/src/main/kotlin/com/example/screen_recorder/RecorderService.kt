package com.example.screen_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat

@RequiresApi(Build.VERSION_CODES.Q) // Enforce that this service only runs on Android 10+
class RecorderService : Service() {

    companion object {
        const val CHANNEL_ID = "screen_recorder_channel"
        const val NOTIF_ID = 101
        // Actions
        const val ACTION_START = "com.example.screen_recorder.ACTION_START"
        const val ACTION_STOP = "com.example.screen_recorder.ACTION_STOP"
        const val ACTION_PAUSE = "com.example.screen_recorder.ACTION_PAUSE"
        const val ACTION_RESUME = "com.example.screen_recorder.ACTION_RESUME"
        // Static variable to hold the last saved path
        var lastSavedPath: String? = null
    }

    private var isRecording: Boolean = false
    private var isPaused: Boolean = false

    private var mediaProjection: MediaProjection? = null
    private var mediaProjectionCallback: MediaProjection.Callback? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: android.hardware.display.VirtualDisplay? = null

    // File handling for Android 10+
    private var outputUri: Uri? = null
    private var outputPfd: ParcelFileDescriptor? = null

    // Recording settings
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
        // Ensure intent and action are not null
        intent?.action ?: return START_NOT_STICKY // Stop if there's no action

        Log.d("RecorderService", "onStartCommand received action: ${intent.action}")

        when (intent.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
            ACTION_PAUSE -> handlePause()
            ACTION_RESUME -> handleResume()
        }
        return START_STICKY
    }

    private fun handleStart(intent: Intent) {
        if (isRecording) {
            Log.w("RecorderService", "Start action received but already recording.")
            return
        }

        // Extract settings from the intent
        width = intent.getIntExtra("width", 1080)
        height = intent.getIntExtra("height", 1920)
        fps = intent.getIntExtra("fps", 30)
        bitrateKbps = intent.getIntExtra("bitrateKbps", 8000)
        includeAudio = intent.getBooleanExtra("includeAudio", true)

        // Must start as a foreground service before using MediaProjection
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // Android 14+
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        // Acquire MediaProjection
        val resultCode = intent.getIntExtra("resultCode", 0)
        val data: Intent? = intent.getParcelableExtra("data")

        if (resultCode == 0 || data == null) {
            Log.e("RecorderService", "MediaProjection data is invalid. Stopping service.")
            stopSelf()
            return
        }

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)

        // Register callback for MediaProjection state changes
        mediaProjectionCallback = object : MediaProjection.Callback() {
            override fun onStop() {
                Log.d("RecorderService", "MediaProjection stopped")
                if (isRecording) {
                    handleStop()
                }
            }
        }
        mediaProjection?.registerCallback(mediaProjectionCallback!!, null)

        try {
            prepareRecorder()
            startRecording()
            isRecording = true
            isPaused = false
            updateNotification() // Update notification to show recording state
        } catch (e: Exception) {
            Log.e("RecorderService", "Failed to start recording", e)
            cleanupAfterError()
        }
    }

    private fun prepareRecorder() {
        val micPermission = includeAudio && (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)

        // Use the modern MediaRecorder() constructor for API 31+ if available
        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(applicationContext)
        } else {
            MediaRecorder()
        }

        mediaRecorder?.apply {
            if (micPermission) {
                setAudioSource(MediaRecorder.AudioSource.MIC)
            }
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            setVideoEncodingBitRate(bitrateKbps * 1000)
            setVideoFrameRate(fps)
            setVideoSize(width, height)
            if (micPermission) {
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128_000) // 128 kbps
                setAudioSamplingRate(44100) // 44.1 kHz
            }

            // --- Android 10+ File Saving using MediaStore ---
            val resolver = applicationContext.contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, "ScreenRecording_${System.currentTimeMillis()}.mp4")
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/ScreenRecorder")
                put(MediaStore.Video.Media.IS_PENDING, 1) // Mark as pending
            }

            val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            outputUri = resolver.insert(collection, contentValues)

            if (outputUri == null) {
                throw IllegalStateException("Failed to create new MediaStore entry.")
            }

            outputPfd = resolver.openFileDescriptor(outputUri!!, "w")
            setOutputFile(outputPfd!!.fileDescriptor)
            // --- End of MediaStore Logic ---

            prepare()
        }
    }

    private fun startRecording() {
        val surface = mediaRecorder!!.surface
        val densityDpi = resources.displayMetrics.densityDpi
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenRecorder-Display",
            width, height, densityDpi,
            0, // VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR
            surface, null, null
        )
        mediaRecorder?.start()
        Log.d("RecorderService", "Recording started.")
    }

    private fun handlePause() {
        if (!isRecording || isPaused) return
        try {
            mediaRecorder?.pause()
            isPaused = true
            updateNotification()
            Log.d("RecorderService", "Recording paused.")
        } catch (e: Exception) {
            Log.e("RecorderService", "Failed to pause recorder", e)
        }
    }

    private fun handleResume() {
        if (!isRecording || !isPaused) return
        try {
            mediaRecorder?.resume()
            isPaused = false
            updateNotification()
            Log.d("RecorderService", "Recording resumed.")
        } catch (e: Exception) {
            Log.e("RecorderService", "Failed to resume recorder", e)
        }
    }

    private fun handleStop() {
        if (!isRecording) {
            Log.w("RecorderService", "Stop action received but not recording.")
            stopSelf()
            return
        }

        Log.d("RecorderService", "Stopping recording.")
        isRecording = false
        isPaused = false

        // --- SAFE RESOURCE RELEASE - CRUCIAL TO PREVENT CRASHES ---
        // The order is important. Stop the recorder first.
        try {
            mediaRecorder?.stop()
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception stopping MediaRecorder", e)
        }
        try {
            mediaRecorder?.reset()
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception resetting MediaRecorder", e)
        }
        try {
            mediaRecorder?.release()
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception releasing MediaRecorder", e)
        }
        mediaRecorder = null

        try {
            virtualDisplay?.release()
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception releasing VirtualDisplay", e)
        }
        virtualDisplay = null

        try {
            mediaProjection?.unregisterCallback(mediaProjectionCallback!!)
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception unregistering MediaProjection callback", e)
        }
        mediaProjectionCallback = null

        try {
            mediaProjection?.stop()
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception stopping MediaProjection", e)
        }
        mediaProjection = null
        // --- END OF SAFE RELEASE ---

        // Mark the file as complete in MediaStore so it appears in the gallery
        if (outputUri != null) {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.IS_PENDING, 0) // No longer pending
                }
                applicationContext.contentResolver.update(outputUri!!, values, null, null)
                lastSavedPath = outputUri.toString() // Save the path for retrieval
                Log.d("RecorderService", "File saved and marked as complete: $lastSavedPath")
            } catch (e: Exception) {
                Log.e("RecorderService", "Failed to update MediaStore pending status", e)
                lastSavedPath = null
            }
        } else {
            lastSavedPath = null
        }
        
        // Clean up file descriptors
        try { outputPfd?.close() } catch (e: Exception) { Log.e("RecorderService", "Error closing PFD", e) }
        outputPfd = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun cleanupAfterError() {
        Log.e("RecorderService", "Cleaning up resources after a failure.")
        // Clean up a possibly pending MediaStore item to avoid hidden files
        outputUri?.let { uri ->
            try { contentResolver.delete(uri, null, null) } catch (e: Exception) {
                Log.e("RecorderService", "Error deleting pending MediaStore entry", e)
            }
        }
        outputUri = null
        lastSavedPath = null

        // Unregister callback if not already done
        try {
            mediaProjection?.unregisterCallback(mediaProjectionCallback!!)
        } catch (e: Exception) {
            Log.e("RecorderService", "Exception unregistering MediaProjection callback in cleanup", e)
        }
        mediaProjectionCallback = null

        handleStop() // Use handleStop to safely release all other resources
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val title = when {
            isPaused -> "Recording paused"
            isRecording -> "Recording in progress"
            else -> "Screen Recorder"
        }

        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or legacyMutableFlag()
        )

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

        // Add actions based on state
        if (isRecording) {
            if (isPaused) {
                builder.addAction(0, "Resume", pendingIntentFor(ACTION_RESUME))
            } else {
                builder.addAction(0, "Pause", pendingIntentFor(ACTION_PAUSE))
            }
            builder.addAction(0, "Stop", pendingIntentFor(ACTION_STOP))
        }

        return builder.build()
    }

    private fun pendingIntentFor(action: String): PendingIntent {
        val intent = Intent(this, RecorderService::class.java).apply { this.action = action }
        return PendingIntent.getService(
            this, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or legacyMutableFlag()
        )
    }

    private fun legacyMutableFlag(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0

    private fun createChannel() {
        // Notification channel is required for Android 8.0 (API 26) and above.
        // Since our minimum is 10.0 (API 29), this will always run.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Screen Recorder Controls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notification with controls for the screen recorder"
            enableLights(false)
            enableVibration(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}