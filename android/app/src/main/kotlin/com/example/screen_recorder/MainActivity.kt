package com.example.screen_recorder

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.screen_recorder/recorder"
    private val EVENT_CHANNEL = "com.example.screen_recorder/events"

    private var pendingWidth: Int = 1080
    private var pendingHeight: Int = 1920
    private var pendingFps: Int = 30
    private var pendingBitrateKbps: Int = 8000
    private var pendingIncludeAudio: Boolean = true
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        private var instance: MainActivity? = null

        fun sendEventToFlutter(event: String) {
            instance?.sendEvent(event)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up EventChannel for state updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "serviceStart" -> {
                    startServiceWithAction(RecorderService.ACTION_START)
                    result.success(true)
                }
                "servicePause" -> {
                    startServiceWithAction(RecorderService.ACTION_PAUSE)
                    result.success(true)
                }
                "serviceResume" -> {
                    startServiceWithAction(RecorderService.ACTION_RESUME)
                    result.success(true)
                }
                "serviceStop" -> {
                    startServiceWithAction(RecorderService.ACTION_STOP)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "requestProjectionAndStart" -> {
                    val args = call.arguments as? Map<*, *>
                    pendingWidth = (args?.get("width") as? Int) ?: 1080
                    pendingHeight = (args?.get("height") as? Int) ?: 1920
                    pendingFps = (args?.get("fps") as? Int) ?: 30
                    pendingBitrateKbps = (args?.get("bitrateKbps") as? Int) ?: 8000
                    pendingIncludeAudio = (args?.get("includeAudio") as? Boolean) ?: true
                    requestProjection()
                    result.success(true)
                }
                "requestRecordAudioPermission" -> {
                    requestRecordAudioPermission()
                    result.success(true)
                }
                "requestRuntimePermissions" -> {
                    requestRuntimePermissions()
                    result.success(true)
                }
                "serviceStopAndGetPath" -> {
                    // Stop the service and return the last saved path
                    startServiceWithAction(RecorderService.ACTION_STOP)
                    // Wait a short moment to ensure handleStop() runs
                    Handler(Looper.getMainLooper()).postDelayed({
                        result.success(RecorderService.lastSavedPath)
                    }, 500)
                }
                "resolveLastRecordingPath" -> {
                    // Return the last saved path without stopping the service
                    result.success(RecorderService.lastSavedPath)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestRecordAudioPermission() {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1002)
        }
    }

    private fun requestProjection() {
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mpm.createScreenCaptureIntent()
        startActivityForResult(intent, 2001)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    private fun requestRuntimePermissions() {
        val perms = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.READ_MEDIA_VIDEO
            }
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.RECORD_AUDIO
            }
        } else if (Build.VERSION.SDK_INT >= 29) {
            if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.READ_EXTERNAL_STORAGE
            }
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.RECORD_AUDIO
            }
        } else {
            if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.READ_EXTERNAL_STORAGE
            }
            if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.WRITE_EXTERNAL_STORAGE
            }
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                perms += Manifest.permission.RECORD_AUDIO
            }
        }
        if (perms.isNotEmpty()) {
            requestPermissions(perms.toTypedArray(), 1003)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 2001 && resultCode == Activity.RESULT_OK && data != null) {
            val intent = Intent(this, RecorderService::class.java).apply {
                action = RecorderService.ACTION_START
                putExtra("resultCode", resultCode)
                putExtra("data", data)
                putExtra("width", pendingWidth)
                putExtra("height", pendingHeight)
                putExtra("fps", pendingFps)
                putExtra("bitrateKbps", pendingBitrateKbps)
                putExtra("includeAudio", pendingIncludeAudio)
            }
            startForegroundServiceCompat(intent)
        }
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun startServiceWithAction(action: String) {
        val intent = Intent(this, RecorderService::class.java).apply { this.action = action }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (action == RecorderService.ACTION_START) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } else {
            startService(intent)
        }
    }

    fun sendEvent(event: String) {
        eventSink?.success(event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("start_from_notification", false)) {
            requestProjection()
        }
    }
}
