package com.example.cpft

import android.content.Context
import android.content.Intent
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.cpft/multicast"
    private val SETTINGS_CHANNEL = "cpft/settings"
    private val MDNS_CHANNEL = "com.example.cpft/mdns"
    private val HOSTNAME_CHANNEL = "com.example.cpft/hostname"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var nsdManager: NsdManager? = null

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

        // mDNS hostname resolution channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MDNS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "resolveHostname" -> {
                    val serviceName = call.argument<String>("serviceName")
                    val serviceType = call.argument<String>("serviceType") ?: "_http._tcp"
                    
                    if (serviceName == null) {
                        result.error("INVALID_ARGS", "serviceName is required", null)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        resolveServiceHostname(serviceName, serviceType, result)
                    } catch (e: Exception) {
                        result.error("RESOLVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Hostname channel - get actual Android .local hostname
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOSTNAME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getActualHostname" -> {
                    try {
                        val hostname = getAndroidHostname()
                        result.success(hostname)
                    } catch (e: Exception) {
                        result.error("HOSTNAME_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getAndroidHostname(): String {
        // Android mDNS hostname is: Android_<ANDROID_ID>
        // ANDROID_ID is an 8-character uppercase hex string
        val androidId = Settings.Secure.getString(
            applicationContext.contentResolver,
            Settings.Secure.ANDROID_ID
        )
        
        // Take last 8 characters and make uppercase
        val shortId = androidId.takeLast(8).uppercase(Locale.ROOT)
        return "Android_$shortId"
    }

    private fun resolveServiceHostname(serviceName: String, serviceType: String, result: MethodChannel.Result) {
        if (nsdManager == null) {
            nsdManager = applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
        }

        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                result.error("RESOLVE_FAILED", "Failed to resolve service: errorCode=$errorCode", null)
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                // Android NSD gives us the IP in serviceInfo.host
                val host = serviceInfo.host
                val ipAddress = host?.hostAddress
                
                println("=== NSD Resolution Debug ===")
                println("Service Name: ${serviceInfo.serviceName}")
                println("Host: $host")
                println("Host.hostName: ${host?.hostName}")
                println("Host.hostAddress: ${host?.hostAddress}")
                println("Host.canonicalHostName: ${host?.canonicalHostName}")
                
                // The canonicalHostName should give us the actual .local hostname
                // like "Android_M874CMBN.local"
                var mdnsHostname = host?.canonicalHostName
                
                // If canonicalHostName is just the IP, try reverse lookup
                if (mdnsHostname == ipAddress || mdnsHostname == null) {
                    println("Canonical hostname is IP or null, trying reverse lookup...")
                    try {
                        // Perform reverse DNS lookup
                        val resolvedHost = host?.canonicalHostName
                        println("Reverse lookup result: $resolvedHost")
                        if (resolvedHost != null && resolvedHost != ipAddress) {
                            mdnsHostname = resolvedHost
                        }
                    } catch (e: Exception) {
                        println("Reverse lookup failed: ${e.message}")
                    }
                }
                
                // Try to get hostname from TXT records as fallback
                var txtHostname: String? = null
                try {
                    val attributes = serviceInfo.attributes
                    if (attributes != null && attributes.containsKey("host")) {
                        val hostBytes = attributes["host"]
                        if (hostBytes != null) {
                            txtHostname = String(hostBytes, Charsets.UTF_8)
                            println("TXT host attribute: $txtHostname")
                        }
                    }
                } catch (e: Exception) {
                    println("Error reading TXT attributes: ${e.message}")
                }
                
                // Priority: canonical hostname (Android_XXX.local) > TXT > IP
                val finalHostname = when {
                    mdnsHostname != null && mdnsHostname.contains(".local") -> {
                        println("✓ Using canonical mDNS hostname: $mdnsHostname")
                        mdnsHostname
                    }
                    txtHostname != null && txtHostname.contains(".local") -> {
                        println("✓ Using TXT hostname: $txtHostname")
                        txtHostname
                    }
                    else -> {
                        println("✓ Falling back to IP: $ipAddress")
                        ipAddress
                    }
                }
                
                val resultMap = mapOf(
                    "hostname" to finalHostname,
                    "canonicalHostName" to mdnsHostname,
                    "txtHost" to txtHostname,
                    "hostAddress" to ipAddress,
                    "port" to serviceInfo.port,
                    "serviceName" to serviceInfo.serviceName
                )
                
                println("=== Final Result: $finalHostname ===")
                result.success(resultMap)
            }
        }

        // Create a temporary service info for resolution
        val serviceInfo = NsdServiceInfo().apply {
            this.serviceName = serviceName
            this.serviceType = serviceType
        }

        nsdManager?.resolveService(serviceInfo, resolveListener)
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
