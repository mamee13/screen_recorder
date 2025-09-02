package com.example.screen_recorder

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.screen_recorder/recorder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
    }

    private fun startServiceWithAction(action: String) {
        val intent = Intent(this, RecorderService::class.java).apply { this.action = action }
        startService(intent)
    }
}
