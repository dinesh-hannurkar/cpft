package com.example.cpft

import android.content.Context
import android.content.Intent
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.annotation.RequiresApi
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
    private val WIFI_CHANNEL = "com.example.cpft/wifi"
    private val HOTSPOT_CHANNEL = "com.example.cpft/hotspot"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var nsdManager: NsdManager? = null
    private lateinit var wifiManager: WifiManager
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        
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

        // WiFi management channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")
                    val security = call.argument<String>("security") ?: "WPA"

                    if (ssid == null) {
                        result.error("INVALID_ARGS", "ssid is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        connectToWifi(ssid, password, security, result)
                    } catch (e: Exception) {
                        result.error("WIFI_CONNECT_ERROR", e.message, null)
                    }
                }
                "disconnectWifi" -> {
                    try {
                        disconnectWifi(result)
                    } catch (e: Exception) {
                        result.error("WIFI_DISCONNECT_ERROR", e.message, null)
                    }
                }
                "getCurrentWifi" -> {
                    try {
                        val currentSsid = getCurrentWifiSsid()
                        result.success(currentSsid)
                    } catch (e: Exception) {
                        result.error("WIFI_INFO_ERROR", e.message, null)
                    }
                }
                "openWifiSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WIFI_SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Hotspot management channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocalOnlyHotspot" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startLocalOnlyHotspot(result)
                    } else {
                        result.error("UNSUPPORTED", "Local-only hotspot requires Android O+", null)
                    }
                }
                "stopLocalOnlyHotspot" -> {
                    stopLocalOnlyHotspot(result)
                }
                "getHotspotDetails" -> {
                    getHotspotDetails(result)
                }
                "isHotspotRunning" -> {
                    val isRunning = hotspotReservation != null
                    result.success(isRunning)
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

    private fun connectToWifi(ssid: String, password: String?, security: String, result: MethodChannel.Result) {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        android.util.Log.d("WiFiConnect", "Attempting to connect to SSID: '$ssid', password: '${password?.take(4)}****', security: '$security'")

        // Check if WiFi is enabled
        if (!wifiManager.isWifiEnabled) {
            android.util.Log.d("WiFiConnect", "WiFi is not enabled")
            result.error("WIFI_DISABLED", "WiFi is not enabled", null)
            return
        }

        // Check current connection
        val currentSsid = getCurrentWifiSsid()
        if (currentSsid == ssid) {
            result.success(mapOf("status" to "already_connected", "ssid" to ssid))
            return
        }

        // For Android 10+ (Q), use WifiNetworkSpecifier
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val builder = android.net.wifi.WifiNetworkSpecifier.Builder().setSsid(ssid)
                when (security.uppercase()) {
                    "NOPASS", "OPEN" -> {
                        // No passphrase
                    }
                    "WEP" -> {
                        // WEP unsupported by specifier; fall back to passphrase (most hotspots use WPA2)
                        if (!password.isNullOrEmpty()) builder.setWpa2Passphrase(password)
                    }
                    "WPA", "WPA2" -> {
                        if (!password.isNullOrEmpty()) builder.setWpa2Passphrase(password)
                    }
                    else -> {
                        android.util.Log.d("WiFiConnect", "Unsupported security type for Q+: $security")
                    }
                }

                val specifier = builder.build()

                val request = android.net.NetworkRequest.Builder()
                    .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
                    .setNetworkSpecifier(specifier)
                    .build()

                val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager

                val callback = object : android.net.ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: android.net.Network) {
                        android.util.Log.d("WiFiConnect", "Network available for SSID: $ssid")
                        connectivityManager.bindProcessToNetwork(network)
                        result.success(mapOf("status" to "connected", "ssid" to ssid))
                    }

                    override fun onUnavailable() {
                        android.util.Log.d("WiFiConnect", "Network unavailable for SSID: $ssid")
                        result.error("NETWORK_UNAVAILABLE", "Failed to connect to WiFi network", null)
                    }
                }

                connectivityManager.requestNetwork(request, callback)
                return
            } catch (e: Exception) {
                android.util.Log.e("WiFiConnect", "Specifier error: ${e.message}")
                // Fallback to legacy below
            }
        }

        // Legacy approach (Android 9 and below): create WiFi configuration
        val wifiConfig = when (security.uppercase()) {
            "NOPASS", "OPEN" -> {
                // Open network
                android.net.wifi.WifiConfiguration().apply {
                    SSID = "\"$ssid\""
                    allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)
                }
            }
            "WEP" -> {
                // WEP network
                android.net.wifi.WifiConfiguration().apply {
                    SSID = "\"$ssid\""
                    wepKeys[0] = "\"$password\""
                    wepTxKeyIndex = 0
                    allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)
                    allowedGroupCiphers.set(android.net.wifi.WifiConfiguration.GroupCipher.WEP40)
                }
            }
            "WPA", "WPA2" -> {
                // WPA/WPA2 network
                android.net.wifi.WifiConfiguration().apply {
                    SSID = "\"$ssid\""
                    if (password != null) {
                        preSharedKey = "\"$password\""
                    }
                    allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.WPA_PSK)
                    allowedPairwiseCiphers.set(android.net.wifi.WifiConfiguration.PairwiseCipher.TKIP)
                    allowedPairwiseCiphers.set(android.net.wifi.WifiConfiguration.PairwiseCipher.CCMP)
                    allowedGroupCiphers.set(android.net.wifi.WifiConfiguration.GroupCipher.TKIP)
                    allowedGroupCiphers.set(android.net.wifi.WifiConfiguration.GroupCipher.CCMP)
                    status = android.net.wifi.WifiConfiguration.Status.ENABLED
                }
            }
            else -> {
                android.util.Log.d("WiFiConnect", "Unsupported security type: $security")
                result.error("UNSUPPORTED_SECURITY", "Unsupported security type: $security", null)
                return
            }
        }

        android.util.Log.d("WiFiConnect", "Created WiFi config - SSID: '${wifiConfig.SSID}', preSharedKey: '${wifiConfig.preSharedKey}'")

        try {
            // Add network configuration
            val networkId = wifiManager.addNetwork(wifiConfig)
            android.util.Log.d("WiFiConnect", "Added network with ID: $networkId")

            if (networkId == -1) {
                android.util.Log.d("WiFiConnect", "Failed to add network configuration")
                result.error("NETWORK_ADD_FAILED", "Failed to add WiFi network configuration", null)
                return
            }

            // Enable the network
            val enableSuccess = wifiManager.enableNetwork(networkId, true)
            android.util.Log.d("WiFiConnect", "Enable network success: $enableSuccess")

            if (!enableSuccess) {
                android.util.Log.d("WiFiConnect", "Failed to enable network")
                result.error("NETWORK_ENABLE_FAILED", "Failed to enable WiFi network", null)
                return
            }

            // Disconnect from current network and reconnect to new one
            wifiManager.disconnect()
            val reconnectSuccess = wifiManager.reconnect()
            android.util.Log.d("WiFiConnect", "Reconnect success: $reconnectSuccess")

            if (reconnectSuccess) {
                // Wait a bit for connection to establish
                Thread.sleep(2000)

                // Check if connection was successful
                val newCurrentSsid = getCurrentWifiSsid()
                android.util.Log.d("WiFiConnect", "Current SSID after connection: '$newCurrentSsid', target SSID: '$ssid'")
                if (newCurrentSsid == ssid) {
                    android.util.Log.d("WiFiConnect", "Successfully connected to $ssid")
                    result.success(mapOf("status" to "connected", "ssid" to ssid))
                } else {
                    android.util.Log.d("WiFiConnect", "Connection initiated but not yet confirmed")
                    result.success(mapOf("status" to "connecting", "ssid" to ssid, "message" to "Connection initiated, may take a few seconds"))
                }
            } else {
                android.util.Log.d("WiFiConnect", "Reconnect failed")
                result.error("RECONNECT_FAILED", "Failed to reconnect to WiFi network", null)
            }

        } catch (e: Exception) {
            android.util.Log.e("WiFiConnect", "Error configuring WiFi: ${e.message}")
            result.error("WIFI_CONFIG_ERROR", "Error configuring WiFi: ${e.message}", null)
        }
    }

    private fun disconnectWifi(result: MethodChannel.Result) {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        try {
            val disconnectSuccess = wifiManager.disconnect()
            if (disconnectSuccess) {
                result.success(mapOf("status" to "disconnected"))
            } else {
                result.error("DISCONNECT_FAILED", "Failed to disconnect from WiFi", null)
            }
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", "Error disconnecting WiFi: ${e.message}", null)
        }
    }

    private fun getCurrentWifiSsid(): String? {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiInfo = wifiManager.connectionInfo

        return wifiInfo?.ssid?.removeSurrounding("\"")
    }

    // ════════════════════════════════════════════════════════════════
    // Start Local-Only Hotspot
    // ════════════════════════════════════════════════════════════════
    @RequiresApi(Build.VERSION_CODES.O)
    private fun startLocalOnlyHotspot(result: MethodChannel.Result) {
        try {
            // Stop existing hotspot if running
            if (hotspotReservation != null) {
                hotspotReservation?.close()
                hotspotReservation = null
            }

            // Start new hotspot
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {

                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        super.onStarted(reservation)
                        hotspotReservation = reservation

                        try {
                            // Get hotspot configuration
                            val config = reservation.wifiConfiguration

                            val ssid = config?.SSID?.removeSurrounding("\"") ?: "Unknown"
                            val password = config?.preSharedKey ?: "Unknown"
                            val securityType = getSecurityType(config)

                            android.util.Log.d("Hotspot", "Started - SSID: $ssid, Password: $password, Security: $securityType")

                            // Return success with hotspot details
                            val resultMap = mapOf(
                                "success" to true,
                                "ssid" to ssid,
                                "password" to password,
                                "securityType" to securityType,
                                "message" to "Hotspot started successfully"
                            )
                            result.success(resultMap)

                        } catch (e: Exception) {
                            android.util.Log.e("Hotspot", "Error getting config: ${e.message}")
                            result.error("CONFIG_ERROR", e.message, null)
                        }
                    }

                    override fun onStopped() {
                        super.onStopped()
                        hotspotReservation = null
                        android.util.Log.d("Hotspot", "Hotspot stopped")
                    }

                    override fun onFailed(reason: Int) {
                        super.onFailed(reason)
                        hotspotReservation = null

                        val errorMsg = when (reason) {
                            WifiManager.LocalOnlyHotspotCallback.ERROR_GENERIC ->
                                "Generic error occurred"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                                "Incompatible mode - WiFi is on"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
                                "No WiFi channel available"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
                                "Tethering is disallowed"
                            else -> "Unknown error: $reason"
                        }

                        android.util.Log.e("Hotspot", "Failed: $errorMsg")
                        result.error("HOTSPOT_START_FAILED", errorMsg, null)
                    }
                },
                Handler(Looper.getMainLooper())
            )

        } catch (e: Exception) {
            android.util.Log.e("Hotspot", "Exception: ${e.message}")
            result.error("EXCEPTION", e.message, null)
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Stop Local-Only Hotspot
    // ════════════════════════════════════════════════════════════════
    private fun stopLocalOnlyHotspot(result: MethodChannel.Result) {
        try {
            if (hotspotReservation != null) {
                hotspotReservation?.close()
                hotspotReservation = null
                android.util.Log.d("Hotspot", "Hotspot stopped")
                result.success(mapOf("success" to true, "message" to "Hotspot stopped"))
            } else {
                result.success(mapOf("success" to false, "message" to "No hotspot running"))
            }
        } catch (e: Exception) {
            android.util.Log.e("Hotspot", "Error stopping hotspot: ${e.message}")
            result.error("EXCEPTION", e.message, null)
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Get Hotspot Details
    // ════════════════════════════════════════════════════════════════
    private fun getHotspotDetails(result: MethodChannel.Result) {
        try {
            if (hotspotReservation != null) {
                val config = hotspotReservation?.wifiConfiguration
                val securityType = getSecurityType(config)
                val resultMap = mapOf(
                    "ssid" to (config?.SSID?.removeSurrounding("\"") ?: "Unknown"),
                    "password" to (config?.preSharedKey ?: "Unknown"),
                    "securityType" to securityType,
                    "running" to true
                )
                result.success(resultMap)
            } else {
                result.success(mapOf("running" to false))
            }
        } catch (e: Exception) {
            android.util.Log.e("Hotspot", "Error getting details: ${e.message}")
            result.error("EXCEPTION", e.message, null)
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Get Security Type from WifiConfiguration
    // ════════════════════════════════════════════════════════════════
    private fun getSecurityType(config: android.net.wifi.WifiConfiguration?): String {
        if (config == null) return "UNKNOWN"

        // For local-only hotspots, Android typically uses WPA2-PSK
        // Check if preSharedKey is set (indicates WPA/WPA2)
        if (!config.preSharedKey.isNullOrEmpty()) {
            android.util.Log.d("Hotspot", "Has preSharedKey, returning WPA2")
            return "WPA2"
        }

        // Check for open networks
        if (config.allowedKeyManagement.get(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)) {
            return "nopass"
        }

        // Default to WPA2 for local-only hotspots
        android.util.Log.d("Hotspot", "Defaulting to WPA2 for local-only hotspot")
        return "WPA2"
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
