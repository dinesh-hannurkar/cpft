package com.example.cpft

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.cpft/multicast"
    private val SETTINGS_CHANNEL = "cpft/settings"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Multicast lock channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        acquireMulticastLock()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK_ERROR", e.message, null)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        releaseMulticastLock()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Settings channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager

        // Acquire multicast lock
        if (multicastLock == null || !multicastLock!!.isHeld) {
            multicastLock = wifiManager.createMulticastLock("cpft_multicast_lock")
            multicastLock?.setReferenceCounted(false)
            multicastLock?.acquire()
            println("MulticastLock acquired")
        }

        // Acquire wake lock to prevent device sleep during discovery
        if (wakeLock == null || !wakeLock!!.isHeld) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "cpft:discovery_wake_lock"
            )
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes
            println("WakeLock acquired")
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
                println("MulticastLock released")
            }
        }
        multicastLock = null

        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                println("WakeLock released")
            }
        }
        wakeLock = null
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
