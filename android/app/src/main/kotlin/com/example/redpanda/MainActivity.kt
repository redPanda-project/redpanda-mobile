package com.example.redpanda

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "redpanda/foreground_service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    ensureNotificationPermission()
                    val intent = Intent(this, RpForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, RpForegroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 13+: the foreground service runs without this permission, but
     * its persistent notification would be invisible — ask once so the user
     * can see (and via its settings silence) the background indicator.
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }
}
