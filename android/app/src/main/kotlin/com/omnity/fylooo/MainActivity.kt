package com.omnity.fylooo

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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.omnity.fylooo/multicast"
    private val SETTINGS_CHANNEL = "fylooo/settings"
    private val MDNS_CHANNEL = "com.omnity.fylooo/mdns"
    private val HOSTNAME_CHANNEL = "com.omnity.fylooo/hostname"
    private val WIFI_CHANNEL = "com.omnity.fylooo/wifi"
    private val WIFI_DIRECT_CHANNEL = "com.omnity.fylooo/wifi_direct"
    private val HOTSPOT_CHANNEL = "com.omnity.fylooo/hotspot"
    private val NATIVE_SENDER_CHANNEL = "com.omnity.fylooo/native_sender"
    private val NATIVE_RECEIVER_CHANNEL = "com.omnity.fylooo/native_receiver"
    private val NATIVE_RECEIVER_PROGRESS_CHANNEL = "com.omnity.fylooo/native_receiver_progress"
    private val WIFI_PERFORMANCE_CHANNEL = "com.omnity.fylooo/wifi_performance"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var transferWakeLock: PowerManager.WakeLock? = null
    private var nsdManager: NsdManager? = null
    private lateinit var wifiManager: WifiManager
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var nativeDataReceiver: NativeDataReceiver? = null
    private var nativeReceiverProgressChannel: MethodChannel? = null
    internal val mainHandler = Handler(Looper.getMainLooper())
    private var nativeReceiverMethodChannel: MethodChannel? = null
    private var wifiDirectManager: WiFiDirectManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        android.util.Log.d("MainActivity", "configureFlutterEngine called")
        super.configureFlutterEngine(flutterEngine)
        
        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        
        // Native receiver method channel for file registration
        nativeReceiverMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_RECEIVER_CHANNEL + "_method")
        nativeReceiverMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startReceiver" -> {
                    try {
                        if (nativeDataReceiver == null) {
                            nativeDataReceiver = NativeDataReceiver(applicationContext, this, nativeReceiverMethodChannel!!)
                        }
                        nativeDataReceiver?.start()
                        android.util.Log.d("MainActivity", "Native receiver started on demand")
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Failed to start native receiver: ${e.message}")
                        result.error("START_RECEIVER_ERROR", e.message, null)
                    }
                }
                "registerIncoming" -> {
                    val transferId = call.argument<String>("transferId")
                    val path = call.argument<String>("path")

                    if (transferId == null || path == null) {
                        result.error("INVALID_ARGS", "transferId and path are required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        android.util.Log.d("MainActivity", "registerIncoming called: $transferId -> $path")
                        // Receiver must already be started - don't create new instance
                        if (nativeDataReceiver == null) {
                            android.util.Log.e("MainActivity", "Native receiver not started yet")
                            result.error("RECEIVER_NOT_STARTED", "Call startReceiver first", null)
                            return@setMethodCallHandler
                        }
                        nativeDataReceiver?.registerIncomingFile(transferId, path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REGISTER_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Native receiver progress channel
        nativeReceiverProgressChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_RECEIVER_PROGRESS_CHANNEL)
        
        // WiFi Performance Lock Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_PERFORMANCE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireWifiLock" -> {
                    acquireWifiPerformanceLock()
                    result.success(true)
                }
                "releaseWifiLock" -> {
                    releaseWifiPerformanceLock()
                    result.success(true)
                }
                "acquireTransferWakeLock" -> {
                    acquireTransferWakeLock()
                    result.success(true)
                }
                "releaseTransferWakeLock" -> {
                    releaseTransferWakeLock()
                    result.success(true)
                }
                "enableSustainedPerformance" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        enableSustainedPerformanceMode()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "disableSustainedPerformance" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        disableSustainedPerformanceMode()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "requestBatteryOptimizationExemption" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        requestBatteryOptimizationExemption(result)
                    } else {
                        result.success(true) // Not needed on older versions
                    }
                }
                "checkBatteryOptimizationStatus" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        checkBatteryOptimizationStatus(result)
                    } else {
                        result.success(true) // Not needed on older versions
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // WiFi info channel for frequency detection
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWifiFrequency" -> {
                    try {
                        val wifiInfo = wifiManager.connectionInfo
                        if (wifiInfo != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            val frequency = wifiInfo.frequency // in MHz
                            val band = when {
                                frequency in 2400..2500 -> "2.4GHz"
                                frequency in 5000..5900 -> "5GHz"
                                frequency in 5925..7125 -> "6GHz" // WiFi 6E
                                else -> "Unknown"
                            }
                            result.success(mapOf(
                                "frequency" to frequency,
                                "band" to band
                            ))
                        } else {
                            result.success(mapOf(
                                "frequency" to 0,
                                "band" to "Unknown"
                            ))
                        }
                    } catch (e: Exception) {
                        result.error("WIFI_ERROR", e.message, null)
                    }
                }
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")
                    val security = call.argument<String>("security") ?: "WPA"
                    
                    if (ssid == null) {
                        result.error("INVALID_ARGS", "SSID is required", null)
                        return@setMethodCallHandler
                    }
                    
                    connectToWifi(ssid, password, security, result)
                }
                "disconnectWifi" -> {
                    disconnectWifi(result)
                }
                "disableWifi" -> {
                    disableWifi(result)
                }
                "openWifiSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_ERROR", "Failed to open WiFi settings: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // WiFi Direct channel for P2P high-speed transfers
        val wifiDirectChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_DIRECT_CHANNEL)
        wifiDirectManager = WiFiDirectManager(applicationContext, wifiDirectChannel)
        
        wifiDirectChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isWifiDirectSupported" -> {
                    result.success(wifiDirectManager?.initialize() ?: false)
                }
                "getThisDevice" -> {
                    try {
                        result.success(wifiDirectManager?.getThisDeviceInfo())
                    } catch (e: Exception) {
                        result.error("WIFI_DIRECT_ERROR", e.message, null)
                    }
                }
                "startDiscovery" -> {
                    val success = wifiDirectManager?.startDiscovery() ?: false
                    result.success(success)
                }
                "stopDiscovery" -> {
                    wifiDirectManager?.stopDiscovery()
                    result.success(true)
                }
                "createGroup" -> {
                    wifiDirectManager?.createGroup(result)
                }
                "connect" -> {
                    val peerId = call.argument<String>("peerId")
                    if (peerId == null) {
                        result.error("INVALID_ARGS", "peerId required", null)
                        return@setMethodCallHandler
                    }
                    wifiDirectManager?.connect(peerId) { success, ip, port ->
                        if (success && ip != null && port != null) {
                            result.success(mapOf(
                                "peerId" to peerId,
                                "ipAddress" to ip,
                                "port" to port
                            ))
                        } else {
                            result.error("CONNECT_FAILED", "Connection failed", null)
                        }
                    }
                }
                "connectToGroup" -> {
                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")

                    if (ssid == null || password == null) {
                        result.error("INVALID_ARGS", "ssid and password required", null)
                        return@setMethodCallHandler
                    }
                    wifiDirectManager?.connectToGroup(ssid, password, result)
                }
                "removeGroup" -> {
                    wifiDirectManager?.disconnect()
                    result.success(true)
                }
                "disconnect" -> {
                    wifiDirectManager?.disconnect()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Local-Only Hotspot Channel
        val hotspotChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL)
        hotspotChannel.setMethodCallHandler { call, result ->
            // ... (existing handler logic) ...
            when (call.method) {
                "startLocalOnlyHotspot" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startLocalOnlyHotspot(result)
                    } else {
                        result.error("UNSUPPORTED", "Local-only hotspot requires Android 8.0+", null)
                    }
                }
                "stopLocalOnlyHotspot" -> {
                    stopLocalOnlyHotspot(result)
                }
                "getHotspotDetails" -> {
                    getHotspotDetails(result)
                }
                "isHotspotRunning" -> {
                    result.success(hotspotReservation != null)
                }
                else -> result.notImplemented()
            }
        }

        // Native QUIC Plugin Registration
        try {
             val quicChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cpft.quic")
             QuicNativePlugin.register(applicationContext, quicChannel)
             android.util.Log.d("MainActivity", "Registered QuicNativePlugin")
        } catch (e: Exception) {
             android.util.Log.e("MainActivity", "Failed to register QuicNativePlugin: ${e.message}")
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

    private fun acquireWifiPerformanceLock() {
        try {
            if (wifiLock == null || !wifiLock!!.isHeld) {
                // Use HIGH_PERF mode to prevent WiFi power saving
                wifiLock = wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "cpft:transfer_wifi_lock"
                )
                wifiLock?.setReferenceCounted(false)
                wifiLock?.acquire()
                android.util.Log.d("WiFiPerformance", "✅ High-performance WiFi lock acquired")
                println("WiFi Performance Lock acquired - power saving disabled")
            }
        } catch (e: Exception) {
            android.util.Log.e("WiFiPerformance", "Failed to acquire WiFi lock: ${e.message}")
        }
    }

    private fun releaseWifiPerformanceLock() {
        try {
            wifiLock?.let {
                if (it.isHeld) {
                    it.release()
                    android.util.Log.d("WiFiPerformance", "✅ High-performance WiFi lock released")
                    println("WiFi Performance Lock released")
                }
            }
            wifiLock = null
        } catch (e: Exception) {
            android.util.Log.e("WiFiPerformance", "Failed to release WiFi lock: ${e.message}")
        }
    }

    private fun acquireTransferWakeLock() {
        try {
            if (transferWakeLock == null || !transferWakeLock!!.isHeld) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                
                // Partial wake lock - keeps CPU running but allows screen off
                transferWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "cpft:transfer_wake_lock"
                )
                transferWakeLock?.setReferenceCounted(false)
                // Acquire for 10 minutes max (auto-release safety)
                transferWakeLock?.acquire(10 * 60 * 1000L)
                android.util.Log.d("TransferWakeLock", "✅ Partial wake lock acquired (CPU stays awake)")
                println("Transfer Wake Lock acquired - CPU will not sleep during transfer")
            }
        } catch (e: Exception) {
            android.util.Log.e("TransferWakeLock", "Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun releaseTransferWakeLock() {
        try {
            transferWakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    android.util.Log.d("TransferWakeLock", "✅ Partial wake lock released")
                    println("Transfer Wake Lock released")
                }
            }
            transferWakeLock = null
        } catch (e: Exception) {
            android.util.Log.e("TransferWakeLock", "Failed to release wake lock: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun enableSustainedPerformanceMode() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            if (powerManager.isSustainedPerformanceModeSupported) {
                window.setSustainedPerformanceMode(true)
                android.util.Log.d("Performance", "✅ Sustained performance mode enabled")
                println("Sustained Performance Mode enabled - system will prioritize performance")
            } else {
                android.util.Log.d("Performance", "⚠️ Sustained performance mode not supported on this device")
            }
        } catch (e: Exception) {
            android.util.Log.e("Performance", "Failed to enable sustained performance mode: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun disableSustainedPerformanceMode() {
        try {
            window.setSustainedPerformanceMode(false)
            android.util.Log.d("Performance", "✅ Sustained performance mode disabled")
            println("Sustained Performance Mode disabled")
        } catch (e: Exception) {
            android.util.Log.e("Performance", "Failed to disable sustained performance mode: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun requestBatteryOptimizationExemption(result: MethodChannel.Result) {
        try {
            val packageName = packageName
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
                android.util.Log.d("BatteryOpt", "✅ App is already exempt from battery optimization")
                result.success(true)
            } else {
                // Request exemption from battery optimization
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.data = android.net.Uri.parse("package:$packageName")
                startActivity(intent)
                android.util.Log.d("BatteryOpt", "📱 Requesting battery optimization exemption")
                result.success(false)
            }
        } catch (e: Exception) {
            android.util.Log.e("BatteryOpt", "Failed to request battery optimization exemption: ${e.message}")
            result.error("BATTERY_OPT_ERROR", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun checkBatteryOptimizationStatus(result: MethodChannel.Result) {
        try {
            val packageName = packageName
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val isExempt = powerManager.isIgnoringBatteryOptimizations(packageName)
            result.success(isExempt)
        } catch (e: Exception) {
            android.util.Log.e("BatteryOpt", "Failed to check battery optimization status: ${e.message}")
            result.error("BATTERY_OPT_ERROR", e.message, null)
        }
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

    private fun disableWifi(result: MethodChannel.Result) {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        try {
            // On Android 10+ (Q), we cannot programmatically disable WiFi
            // We can only disconnect from the current network
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                android.util.Log.d("WiFiDisable", "Android 10+ detected, disconnecting from WiFi instead of disabling")
                val disconnectSuccess = wifiManager.disconnect()
                if (disconnectSuccess) {
                    result.success(mapOf("status" to "disconnected", "note" to "WiFi disconnected (Android 10+ limitation)"))
                } else {
                    result.error("DISCONNECT_FAILED", "Failed to disconnect from WiFi", null)
                }
            } else {
                // On Android 9 and below, we can actually disable WiFi
                @Suppress("DEPRECATION")
                val disableSuccess = wifiManager.setWifiEnabled(false)
                android.util.Log.d("WiFiDisable", "WiFi disable success: $disableSuccess")
                if (disableSuccess) {
                    result.success(mapOf("status" to "disabled"))
                } else {
                    result.error("DISABLE_FAILED", "Failed to disable WiFi", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("WiFiDisable", "Error disabling WiFi: ${e.message}")
            result.error("DISABLE_ERROR", "Error disabling WiFi: ${e.message}", null)
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
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            
            // CRITICAL: WiFi handling differs by Android version
            // Android 10+: WiFi MUST be enabled but NOT connected to any network
            // Android 9-: WiFi must be completely disabled
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: Ensure WiFi is enabled, then disconnect from any network
                android.util.Log.d("Hotspot", "Android 10+ detected")
                
                if (!wifiManager.isWifiEnabled) {
                    android.util.Log.d("Hotspot", "WiFi is disabled, enabling it for hotspot...")
                    @Suppress("DEPRECATION")
                    wifiManager.setWifiEnabled(true)
                    Thread.sleep(1000) // Wait for WiFi to enable
                }
                
                // Disconnect from any connected network
                if (wifiManager.connectionInfo?.networkId != -1) {
                    android.util.Log.d("Hotspot", "Disconnecting from current WiFi network...")
                    wifiManager.disconnect()
                    Thread.sleep(500)
                }
            } else {
                // Android 9 and below: Disable WiFi completely
                if (wifiManager.isWifiEnabled) {
                    android.util.Log.d("Hotspot", "Android 9 or below, disabling WiFi completely")
                    @Suppress("DEPRECATION")
                    wifiManager.setWifiEnabled(false)
                    Thread.sleep(1000)
                }
            }

            // Stop existing hotspot if running
            if (hotspotReservation != null) {
                hotspotReservation?.close()
                hotspotReservation = null
            }

            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    @RequiresApi(Build.VERSION_CODES.O)
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        super.onStarted(reservation)
                        hotspotReservation = reservation

                        try {
                            val config = reservation.wifiConfiguration
                            val ssid = config?.SSID ?: "Unknown"
                            val password = config?.preSharedKey ?: "No password"
                            val securityType = getSecurityType(config)

                            android.util.Log.d("Hotspot", "Started - SSID: $ssid, Password: $password, Security: $securityType")

                            result.success(
                                mapOf(
                                    "success" to true,
                                    "ssid" to ssid,
                                    "password" to password,
                                    "securityType" to securityType,
                                    "message" to "Hotspot started successfully"
                                )
                            )
                        } catch (e: Exception) {
                            android.util.Log.e("Hotspot", "Error getting config: ${e.message}")
                            result.error("CONFIG_ERROR", e.message, null)
                        }
                    }

                    override fun onStopped() {
                        super.onStopped()
                        android.util.Log.d("Hotspot", "Hotspot stopped")
                        hotspotReservation = null
                    }

                    override fun onFailed(reason: Int) {
                        super.onFailed(reason)
                        val errorMsg = when (reason) {
                            WifiManager.LocalOnlyHotspotCallback.ERROR_GENERIC ->
                                "Generic error occurred. Make sure WiFi is enabled and you're not connected to a network."
                            WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                                "Incompatible mode - another app may be using WiFi"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
                                "No available channel"
                            WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
                                "Tethering is not allowed on this device"
                            else -> "Unknown error: $reason"
                        }

                        android.util.Log.e("Hotspot", "Failed: $errorMsg")
                        result.error("HOTSPOT_ERROR", errorMsg, null)
                        hotspotReservation = null
                    }
                },
                null
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

    // ════════════════════════════════════════════════════════════════
    // Native File Sender
    // ════════════════════════════════════════════════════════════════
    private fun sendFile(ip: String, port: Int, filePath: String, transferId: String, chunkSize: Int, result: MethodChannel.Result) {
        Thread {
            try {
                val socket = java.net.Socket(ip, port)
                val output = java.io.DataOutputStream(java.io.BufferedOutputStream(socket.getOutputStream()))
                val file = java.io.File(filePath)
                val fileChannel = java.io.FileInputStream(file).channel
                val fileSize = file.length()
                var bytesSent = 0L
                var index = 0

                // Prepare transferId bytes
                val tidBytes = transferId.toByteArray(Charsets.UTF_8)
                val tidLen = tidBytes.size.toByte()

                while (bytesSent < fileSize) {
                    val remaining = fileSize - bytesSent
                    val thisChunkSize = if (remaining > chunkSize) chunkSize else remaining.toInt()
                    val buffer = java.nio.ByteBuffer.allocate(thisChunkSize)
                    val read = fileChannel.read(buffer)
                    if (read == -1) break
                    buffer.flip()
                    val chunkData = ByteArray(read)
                    buffer.get(chunkData)

                    // Frame: [len:int32][payload]  (DATA SOCKET - NO TYPE BYTE)
                    // payload: [tidLen:byte][tid][index:int32][isLast:byte][data]
                    val isLast = (bytesSent + read) >= fileSize
                    val payload = java.io.ByteArrayOutputStream()
                    payload.write(tidLen.toInt())
                    payload.write(tidBytes)
                    val indexBytes = java.nio.ByteBuffer.allocate(4).putInt(index).array()
                    payload.write(indexBytes)
                    payload.write(if (isLast) 1 else 0)
                    payload.write(chunkData)
                    val payloadBytes = payload.toByteArray()

                    val frameLen = payloadBytes.size  // ✅ Only payload length
                    output.writeInt(frameLen)         // int32 payload length
                    output.write(payloadBytes)        // payload only

                    // Batch flush every 16 chunks for performance
                    if (index % 16 == 0) {
                        output.flush()
                    }

                    bytesSent += read
                    index++
                }

                fileChannel.close()
                output.flush() // Final flush
                output.close()
                socket.close()
                result.success(true)
            } catch (e: Exception) {
                result.error("SEND_FILE_ERROR", e.message, null)
            }
        }.start()
    }

    // Handle progress updates from native receiver
    fun onProgressUpdate(transferId: String, bytes: Int, isLast: Boolean, filePath: String?) {
        // Send progress update via MethodChannel
        try {
            val data = mapOf(
                "transferId" to transferId,
                "bytes" to bytes,
                "isLast" to isLast,
                "filePath" to filePath
            )
            runOnUiThread {
                nativeReceiverProgressChannel?.invokeMethod("onProgress", data)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error sending progress update: ${e.message}")
        }
    }

    fun onAckUpdate(transferId: String, nextExpectedIndex: Int, bytesReceived: Int, completed: Boolean) {
        try {
            val data = mapOf(
                "transferId" to transferId,
                "nextExpectedIndex" to nextExpectedIndex,
                "bytesReceived" to bytesReceived,
                "completed" to completed
            )
            runOnUiThread {
                nativeReceiverProgressChannel?.invokeMethod("onAck", data)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error sending ACK update: ${e.message}")
        }
    }
}

// ════════════════════════════════════════════════════════════════
// Native Data Receiver
// ════════════════════════════════════════════════════════════════

// 🔴 CRITICAL: Chunk model for queue-based receive pipeline
data class Chunk(
    val transferId: String,
    val index: Int,
    val isLast: Boolean,
    val data: ByteArray,
    val offset: Int,
    val length: Int
)

class NativeDataReceiver(
    private val context: android.content.Context,
    private val mainActivity: MainActivity,
    private val methodChannel: MethodChannel
) {
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var serverThread: Thread? = null
    private var writerThread: Thread? = null
    private var isRunning = false
    private val incomingTransfers = mutableMapOf<String, NativeIncoming>()
    private val registeredFiles = mutableMapOf<String, String>() // transferId -> filePath
    
    // 🔴 CRITICAL: BlockingQueue to decouple socket read from disk write
    private val chunkQueue = java.util.concurrent.LinkedBlockingQueue<Chunk>(2048)
    
    // Background executor for ACK dispatch (NOT main thread)
    private val ackExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable).apply { isDaemon = true }
    }
    
    // Tune control/telemetry thresholds: VERY fast ACKs to maximize iOS sender throughput
    private val ackBytesThreshold = 4 * 1024 * 1024                // ACK every 4MB (fast feedback for sender)
    private val ackTimeThresholdMs = 100L                           // ACK at least every 100ms (2x faster)
    private val progressBytesThreshold = 8 * 1024 * 1024            // UI progress every ~8MB
    private val progressTimeThresholdMs = 300L                      // UI progress at least every 300ms

    data class NativeIncoming(
        val channel: java.nio.channels.FileChannel,
        var receivedBytes: Long = 0,
        var lastProgressTime: Long = 0,
        var lastProgressBytes: Long = 0,
        var lastAckTime: Long = 0,
        var lastChunkIndex: Int = -1,
        var lastAckBytes: Long = 0,
        val filePath: String,
        // 🔴 CRITICAL: Reuse direct ByteBuffer to avoid wrap() allocations (4MB for 4MB desktop chunks)
        val writeBuffer: java.nio.ByteBuffer = java.nio.ByteBuffer.allocateDirect(4 * 1024 * 1024)
    )

    fun registerIncomingFile(transferId: String, filePath: String) {
        registeredFiles[transferId] = filePath
        android.util.Log.d("NativeDataReceiver", "Registered incoming file: $transferId -> $filePath")
    }

    fun start() {
        android.util.Log.d("NativeDataReceiver", "start() called")
        if (isRunning) {
            android.util.Log.d("NativeDataReceiver", "Already running")
            return
        }
        isRunning = true

        // 🔴 CRITICAL: Start writer thread BEFORE socket thread
        writerThread = Thread {
            try {
                while (isRunning) {
                    val chunk = chunkQueue.take()  // Blocks until chunk available
                    writeChunkInternal(chunk)
                }
            } catch (e: java.lang.InterruptedException) {
                android.util.Log.d("NativeDataReceiver", "Writer thread interrupted")
            } catch (e: Exception) {
                android.util.Log.e("NativeDataReceiver", "Writer error: ${e.message}")
            }
        }.apply { start() }

        serverThread = Thread {
            try {
                val server = java.net.ServerSocket(53319)
                android.util.Log.d("NativeDataReceiver", "Data server started on port 53319")

                while (isRunning) {
                    val socket = server.accept()
                    android.util.Log.d("NativeDataReceiver", "Accepted data connection from ${socket.inetAddress.hostAddress}")
                    handleDataConnection(socket)
                }

                server.close()
            } catch (e: Exception) {
                android.util.Log.e("NativeDataReceiver", "Server error: ${e.message}")
            }
        }.apply { start() }
    }

    fun stop() {
        isRunning = false
        serverThread?.interrupt()
        writerThread?.interrupt()
        serverThread = null
        writerThread = null

        // Close all file channels
        incomingTransfers.values.forEach { it.channel.close() }
        incomingTransfers.clear()
        registeredFiles.clear()
        chunkQueue.clear()
        
        ackExecutor.shutdown()
    }

    private fun handleDataConnection(socket: java.net.Socket) {
        android.util.Log.d("NativeDataReceiver", "Handling data connection from ${socket.inetAddress.hostAddress}")
        Thread {
            try {
                // Set socket timeout to 60 seconds to allow time for large file transfers
                socket.soTimeout = 60000
                // Reduce latency for the local (127.0.0.1) hop into Dart
                socket.tcpNoDelay = true
                // 🔴 CRITICAL: Large socket buffers for high-throughput localhost transfers
                socket.receiveBufferSize = 32 * 1024 * 1024   // 32MB receive buffer
                socket.sendBufferSize = 32 * 1024 * 1024      // 32MB send buffer
                // Use very large buffer to reduce read syscalls on big chunks
                val input = java.io.DataInputStream(java.io.BufferedInputStream(socket.getInputStream(), 16 * 1024 * 1024))

                while (isRunning) {
                    try {
                        val payloadLen = input.readInt()
                        // Allow up to 16MB payloads to accommodate larger mobile chunk sizes
                        if (payloadLen <= 0 || payloadLen > 16 * 1024 * 1024) {
                            android.util.Log.w("NativeDataReceiver", "Invalid payloadLen: $payloadLen, closing connection")
                            break
                        }

                        val payload = ByteArray(payloadLen)
                        input.readFully(payload)

                        parsePayload(payload)
                    } catch (e: java.io.EOFException) {
                        android.util.Log.d("NativeDataReceiver", "End of stream reached (socket closed by sender)")
                        break
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("NativeDataReceiver", "Connection error: ${e.message}")
            } finally {
                try {
                    socket.close()
                } catch (e: Exception) {
                    android.util.Log.e("NativeDataReceiver", "Error closing socket: ${e.message}")
                }
            }
        }.start()
    }

    private fun parsePayload(buf: ByteArray) {
        var o = 0

        val tidLen = buf[o].toInt() and 0xFF
        o += 1
        val transferId = String(buf, o, tidLen, Charsets.UTF_8)
        o += tidLen

        val index = java.nio.ByteBuffer.wrap(buf, o, 4).int
        o += 4

        val isLast = buf[o].toInt() == 1
        o += 1

        // Avoid extra copies: work with the payload slice directly
        val dataOffset = o
        val dataLength = buf.size - o

        // 🔴 CRITICAL: Queue chunk instead of writing directly (decouple socket from disk I/O)
        try {
            chunkQueue.put(Chunk(transferId, index, isLast, buf, dataOffset, dataLength))
        } catch (e: java.lang.InterruptedException) {
            android.util.Log.e("NativeDataReceiver", "Interrupted while queuing chunk: ${e.message}")
        }
    }

    // 🔴 CRITICAL: Write chunks on dedicated writer thread with reusable ByteBuffer
    private fun writeChunkInternal(chunk: Chunk) {
        try {
            val incoming = incomingTransfers.getOrPut(chunk.transferId) {
                // Use the exact registered path
                val filePath = registeredFiles[chunk.transferId]
                if (filePath == null) {
                    android.util.Log.e("NativeDataReceiver", "No registered path for transfer ${chunk.transferId}")
                    return@getOrPut null!!
                }
                val file = java.io.File(filePath)
                // Ensure parent directory exists
                file.parentFile?.mkdirs()
                val raf = java.io.RandomAccessFile(file, "rw")
                val channel = raf.channel
                android.util.Log.d("NativeDataReceiver", "Created file: ${file.absolutePath}, exists: ${file.exists()}, initial size: ${file.length()}")
                NativeIncoming(channel, filePath = file.absolutePath)
            }

            // 🔴 CRITICAL: Reuse direct ByteBuffer to avoid wrap() allocations
            val writeBuffer = incoming.writeBuffer
            writeBuffer.clear()
            writeBuffer.put(chunk.data, chunk.offset, chunk.length)
            writeBuffer.flip()

            while (writeBuffer.hasRemaining()) {
                incoming.channel.write(writeBuffer)
            }

            // Track last seen chunk index
            if (chunk.index > incoming.lastChunkIndex) {
                incoming.lastChunkIndex = chunk.index
            }

            incoming.receivedBytes += chunk.length.toLong()

            // Send ACK periodically (off main thread)
            val now = System.currentTimeMillis()
            val bytesSinceLastAck = incoming.receivedBytes - incoming.lastAckBytes
            val ackTimeElapsed = now - incoming.lastAckTime
            val shouldAck = bytesSinceLastAck >= ackBytesThreshold || chunk.isLast || ackTimeElapsed >= ackTimeThresholdMs
            if (shouldAck) {
                val nextExpectedIndex = incoming.lastChunkIndex + 1
                // 🔴 CRITICAL: ACKs must NOT touch main thread
                ackExecutor.execute {
                    mainActivity.onAckUpdate(
                        chunk.transferId,
                        nextExpectedIndex,
                        incoming.receivedBytes.toInt(),
                        chunk.isLast
                    )
                }
                incoming.lastAckBytes = incoming.receivedBytes
                incoming.lastAckTime = now
            }

            // Report progress periodically
            val bytesSinceLastProgress = incoming.receivedBytes - incoming.lastProgressBytes
            val timeSinceLastProgress = now - incoming.lastProgressTime
            if (bytesSinceLastProgress >= progressBytesThreshold || timeSinceLastProgress >= progressTimeThresholdMs || chunk.isLast) {
                ackExecutor.execute {
                    mainActivity.onProgressUpdate(chunk.transferId, incoming.receivedBytes.toInt(), chunk.isLast, null)
                }
                incoming.lastProgressBytes = incoming.receivedBytes
                incoming.lastProgressTime = now
            }

            if (chunk.isLast) {
                // Close file channel (let OS flush naturally)
                incoming.channel.close()
                incomingTransfers.remove(chunk.transferId)
                android.util.Log.d("NativeDataReceiver", "✅ Transfer ${chunk.transferId} completed! File saved at: ${incoming.filePath}")
                // Send completion event with file path
                ackExecutor.execute {
                    mainActivity.onProgressUpdate(chunk.transferId, incoming.receivedBytes.toInt(), true, incoming.filePath)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("NativeDataReceiver", "Write error: ${e.message}")
        }
    }

    private fun writeChunk(transferId: String, index: Int, isLast: Boolean, data: ByteArray, offset: Int, length: Int) {
        try {
            val incoming = incomingTransfers.getOrPut(transferId) {
                // Use the exact registered path
                val filePath = registeredFiles[transferId]
                if (filePath == null) {
                    android.util.Log.e("NativeDataReceiver", "No registered path for transfer $transferId")
                    return@getOrPut null!!
                }
                val file = java.io.File(filePath)
                // Ensure parent directory exists
                file.parentFile?.mkdirs()
                val raf = java.io.RandomAccessFile(file, "rw")
                val channel = raf.channel
                android.util.Log.d("NativeDataReceiver", "Created file: ${file.absolutePath}, exists: ${file.exists()}, initial size: ${file.length()}")
                NativeIncoming(channel, filePath = file.absolutePath)
            }

            // Write chunk directly to disk to avoid extra byte[] copies
            var remaining = length
            var writeOffset = offset
            while (remaining > 0) {
                val written = incoming.channel.write(java.nio.ByteBuffer.wrap(data, writeOffset, remaining))
                if (written <= 0) break
                remaining -= written
                writeOffset += written
            }
            // Track last seen chunk index (assumes in-order delivery)
            if (index > incoming.lastChunkIndex) {
                incoming.lastChunkIndex = index
            }

            incoming.receivedBytes += length.toLong()

            // Send ACK periodically based on bytes received to drive sender flow-control
            val now = System.currentTimeMillis()
            val bytesSinceLastAck = incoming.receivedBytes - incoming.lastAckBytes
            val ackTimeElapsed = now - incoming.lastAckTime
            // ACK roughly every 1MB or if a little time has passed to avoid stalls
            val shouldAck = bytesSinceLastAck >= ackBytesThreshold || isLast || ackTimeElapsed >= 800
            if (shouldAck) {
                val nextExpectedIndex = incoming.lastChunkIndex + 1
                mainHandler.post {
                    mainActivity.onAckUpdate(
                        transferId,
                        nextExpectedIndex,
                        incoming.receivedBytes.toInt(),
                        isLast
                    )
                }
                incoming.lastAckBytes = incoming.receivedBytes
                incoming.lastAckTime = now
            }

            // Report progress every 4MB to prevent watchdog timeout without spamming UI
            val bytesSinceLastProgress = incoming.receivedBytes - incoming.lastProgressBytes
            val timeSinceLastProgress = now - incoming.lastProgressTime
            if (bytesSinceLastProgress >= progressBytesThreshold || timeSinceLastProgress >= progressTimeThresholdMs || isLast) {
                mainHandler.post {
                    mainActivity.onProgressUpdate(transferId, incoming.receivedBytes.toInt(), isLast, null)
                }
                incoming.lastProgressBytes = incoming.receivedBytes
                incoming.lastProgressTime = now
            }

            if (isLast) {
                // Force to disk and close
                incoming.channel.force(false)
                val finalSize = java.io.File(incoming.filePath).length()
                android.util.Log.d("NativeDataReceiver", "Closing file, final size: $finalSize bytes")
                incoming.channel.close()
                incomingTransfers.remove(transferId)
                android.util.Log.d("NativeDataReceiver", "✅ Transfer $transferId completed! File saved at: ${incoming.filePath}")
                // Send completion event with file path
                mainHandler.post {
                    mainActivity.onProgressUpdate(transferId, incoming.receivedBytes.toInt(), true, incoming.filePath)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("NativeDataReceiver", "Write error: ${e.message}")
        }
    }
}
