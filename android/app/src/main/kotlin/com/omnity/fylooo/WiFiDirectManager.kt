package com.omnity.fylooo

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import androidx.annotation.RequiresPermission
import io.flutter.plugin.common.MethodChannel
import java.util.Random

/**
 * WiFi Direct (P2P) Manager for Android
 * Enables high-speed peer-to-peer file transfers without router
 */
class WiFiDirectManager(
    private val context: Context,
    private val channel: MethodChannel
) {
    private val TAG = "WiFiDirectManager"
    
    private var p2pManager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private val peers = mutableListOf<WifiP2pDevice>()
    private var isDiscovering = false

    private var pendingConnectCallback: ((Boolean, String?, Int?) -> Unit)? = null

    private var thisDeviceAddress: String? = null
    private var thisDeviceName: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    
    companion object {
        const val TRANSFER_PORT = 53320 // Different from regular P2P port
    }

    fun getThisDeviceInfo(): Map<String, Any?>? {
        val id = thisDeviceAddress
        val name = thisDeviceName
        if (id == null && name == null) return null
        return mapOf(
            "id" to id,
            "name" to name
        )
    }
    
    @RequiresApi(Build.VERSION_CODES.Q)
    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    fun initialize(): Boolean {
        return try {
            p2pManager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            if (p2pManager == null) {
                Log.e(TAG, "WiFi Direct not supported on this device")
                return false
            }
            
            p2pChannel = p2pManager?.initialize(context, Looper.getMainLooper(), null)
            
            // Register receiver early to capture THIS_DEVICE_CHANGED
            val intentFilter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }
            receiver = WiFiDirectBroadcastReceiver(this)
            context.registerReceiver(receiver, intentFilter)
            
            // Request this device info immediately
            val channelRef = p2pChannel
            if (channelRef != null) {
                p2pManager?.requestDeviceInfo(channelRef) { device ->
                    if (device != null) {
                        thisDeviceAddress = device.deviceAddress
                        thisDeviceName = device.deviceName
                        Log.d(TAG, "This device: ${device.deviceName} (${device.deviceAddress})")
                        channel.invokeMethod(
                            "onThisDeviceChanged",
                            mapOf(
                                "id" to device.deviceAddress,
                                "name" to device.deviceName
                            )
                        )
                    }
                }
            }
            
            Log.d(TAG, "WiFi Direct initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize WiFi Direct", e)
            false
        }
    }
    
    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    @RequiresApi(Build.VERSION_CODES.JELLY_BEAN)
    fun startDiscovery(): Boolean {
        if (p2pManager == null || p2pChannel == null) {
            Log.e(TAG, "WiFi Direct not initialized")
            return false
        }
        
        try {
            // Unregister if already registered (to re-register with connection actions)
            try {
                receiver?.let { context.unregisterReceiver(it) }
            } catch (_: Exception) {}
            
            // Register broadcast receiver for all P2P events
            val intentFilter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }
            
            receiver = WiFiDirectBroadcastReceiver(this)
            context.registerReceiver(receiver, intentFilter)
            
            // Start peer discovery
            p2pManager?.discoverPeers(p2pChannel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    isDiscovering = true
                    Log.d(TAG, "Peer discovery started")
                    channel.invokeMethod("onDiscoveryStarted", null)
                }
                
                override fun onFailure(reason: Int) {
                    isDiscovering = false
                    Log.e(TAG, "Peer discovery failed: $reason")
                    channel.invokeMethod("onDiscoveryFailed", mapOf("reason" to reason))
                }
            })
            
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start discovery", e)
            return false
        }
    }
    
    fun createGroup(): Boolean {
        if (p2pManager == null || p2pChannel == null) {
            Log.e(TAG, "WiFi Direct not initialized")
            return false
        }
        
        try {
            // If receiver not registered, register it.
            if (receiver == null) {
                val intentFilter = IntentFilter().apply {
                    addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                    addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                    addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                    addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
                }
                receiver = WiFiDirectBroadcastReceiver(this)
                context.registerReceiver(receiver, intentFilter)
            }
            
            // First, check if we are already a group owner
            p2pManager?.requestGroupInfo(p2pChannel) { group ->
                if (group != null && group.isGroupOwner) {
                    Log.d(TAG, "Already Group Owner, reusing existing group")
                    val payload = mapOf(
                        "ipAddress" to "192.168.49.1",
                        "port" to TRANSFER_PORT,
                        "isGroupOwner" to true,
                        "ssid" to group.networkName,
                        "password" to group.passphrase
                    )
                    channel.invokeMethod("onConnectionEstablished", payload)
                } else {
                    // No group or not owner, proceed to creation
                    // First, remove any existing group to avoid ERROR_BUSY (error code 2)
                    p2pManager?.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                        @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
                        override fun onSuccess() {
                            Log.d(TAG, "Existing group removed, waiting before creating new group...")
                            // Add delay to prevent ERROR_BUSY when creating
                            Handler(Looper.getMainLooper()).postDelayed({
                                createGroupInternal()
                            }, 1000)
                        }
                        
                        @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
                        override fun onFailure(reason: Int) {
                            // If removal fails (e.g., no group exists), proceed to create anyway
                            Log.d(TAG, "No existing group to remove (reason: $reason), creating new group...")
                            createGroupInternal()
                        }
                    })
                }
            }
            
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initiate group creation", e)
            return false
        }
    }
    
    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    private fun createGroupInternal() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                // Disconnect from WiFi to free up radio for 5GHz GO (Fix for single-radio devices like Redmi)
                val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                wifiManager?.disconnect()
                
                // Generate random credentials for 5GHz group
                val random = Random()
                val suffix = random.nextInt(90) + 10
                val ssid = "DIRECT-FY-$suffix"
                val pass = "fylooo13" // 8+ chars

                val config = WifiP2pConfig.Builder()
                    .setNetworkName(ssid)
                    .setPassphrase(pass)
                    .setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_5GHZ)
                    .build()

                Log.d(TAG, "Attempting to create 5GHz Group ($ssid)")
                p2pManager?.createGroup(p2pChannel!!, config, object : WifiP2pManager.ActionListener {
                    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
                    override fun onSuccess() {
                        Log.d(TAG, "5GHz Group creation initiated successfully")
                        requestGroupInfo()
                    }

                    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
                    override fun onFailure(reason: Int) {
                        Log.w(TAG, "5GHz Group creation failed ($reason), falling back to legacy")
                        createLegacyGroup()
                    }
                })
                return
            } catch (e: Exception) {
                Log.e(TAG, "Exception creating 5GHz group, falling back", e)
            }
        }
        createLegacyGroup()
    }

    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    private fun createLegacyGroup() {
        p2pManager?.createGroup(p2pChannel!!, object : WifiP2pManager.ActionListener {
            @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
            override fun onSuccess() {
                Log.d(TAG, "Legacy Group creation initiated successfully")
                requestGroupInfo()
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Group creation failed: $reason")
                val errorMsg = when(reason) {
                    0 -> "ERROR (0): Internal error"
                    1 -> "P2P_UNSUPPORTED (1): P2P is not supported on this device"
                    2 -> "BUSY (2): Framework is busy, try again"
                    else -> "Unknown error ($reason)"
                }
                Log.e(TAG, "Error details: $errorMsg")
                channel.invokeMethod("onGroupCreationFailed", mapOf(
                    "reason" to reason,
                    "message" to errorMsg
                ))
            }
        })
    }

    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    private fun requestGroupInfo() {
        p2pManager?.requestGroupInfo(p2pChannel) { group ->
            if (group != null) {
                Log.d(TAG, "Group info received: SSID=${group.networkName}, isGO=${group.isGroupOwner}")
                if (group.isGroupOwner) {
                    val payload = mapOf(
                        "ipAddress" to "192.168.49.1",
                        "port" to TRANSFER_PORT,
                        "isGroupOwner" to true,
                        "ssid" to group.networkName,
                        "password" to group.passphrase
                    )
                    channel.invokeMethod("onConnectionEstablished", payload)
                }
            } else {
                Log.w(TAG, "Group info is null after creation")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    fun connectToGroup(ssid: String, password: String, callback: (Boolean) -> Unit) {
        try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(password)
                .build()

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) // Important for P2P
                .setNetworkSpecifier(specifier)
                .build()

            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            
            // Unregister any existing callback
            networkCallback?.let { 
                try { connectivityManager.unregisterNetworkCallback(it) } catch(_:Exception){}
            }

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Log.d(TAG, "Connected to P2P Group via Specifier!")
                    // Bind process to ensure traffic goes through this network
                    connectivityManager.bindProcessToNetwork(network)
                    Handler(Looper.getMainLooper()).post {
                        callback(true)
                    }
                }

                override fun onUnavailable() {
                    Log.e(TAG, "P2P Group Unavailable")
                    Handler(Looper.getMainLooper()).post {
                        callback(false)
                    }
                }
                
                override fun onLost(network: Network) {
                    Log.d(TAG, "P2P Network Lost")
                    Handler(Looper.getMainLooper()).post {
                        channel.invokeMethod("onConnectionLost", null)
                    }
                }
            }
            
            connectivityManager.requestNetwork(request, networkCallback!!)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to connect to group", e)
            callback(false)
        }
    }
    
    fun stopDiscovery() {
        try {
            receiver?.let { context.unregisterReceiver(it) }
            receiver = null
            p2pManager?.stopPeerDiscovery(p2pChannel, null)
            isDiscovering = false
            Log.d(TAG, "Peer discovery stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop discovery", e)
        }
    }
    
    fun onPeersAvailable(peerList: WifiP2pDeviceList) {
        peers.clear()
        peers.addAll(peerList.deviceList)
        
        val peerMaps = peers.map { device ->
            mapOf(
                "id" to device.deviceAddress,
                "name" to device.deviceName,
                "isConnected" to (device.status == WifiP2pDevice.CONNECTED)
            )
        }
        
        channel.invokeMethod("onPeersChanged", peerMaps)
        Log.d(TAG, "Found ${peers.size} peers")
    }
    
    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    fun connect(deviceAddress: String, callback: (Boolean, String?, Int?) -> Unit) {
        pendingConnectCallback = callback
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
        }
        
        p2pManager?.connect(p2pChannel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated to $deviceAddress")
                // Wait for connection info in broadcast receiver
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Connection failed: $reason")
                pendingConnectCallback?.invoke(false, null, null)
                pendingConnectCallback = null
            }
        })
    }
    
    fun onConnectionChanged(info: WifiP2pInfo, group: WifiP2pGroup?) {
        if (info.groupFormed) {
            val isGroupOwner = info.isGroupOwner
            val ipAddress = info.groupOwnerAddress?.hostAddress
            
            Log.d(TAG, "P2P Connection established. Group owner: $isGroupOwner, IP: $ipAddress")
            
            val payload = mutableMapOf<String, Any?>(
                "ipAddress" to ipAddress,
                "port" to TRANSFER_PORT,
                "isGroupOwner" to isGroupOwner
            )
            
            
            if (isGroupOwner && group == null) {
                // Send immediate event to update UI (without credentials)
                channel.invokeMethod("onConnectionEstablished", payload)
                
                // Group owner but no group details - request them
                Log.d(TAG, "Group owner detected, requesting group info...")
                p2pManager?.requestGroupInfo(p2pChannel) { groupInfo ->
                    if (groupInfo != null) {
                        Log.d(TAG, "✓ Group info retrieved: SSID=${groupInfo.networkName}, Pass=${groupInfo.passphrase}")
                        payload["ssid"] = groupInfo.networkName
                        payload["password"] = groupInfo.passphrase
                        // Send updated event with credentials
                        channel.invokeMethod("onConnectionEstablished", payload)
                    } else {
                        Log.w(TAG, "Group info still null after request")
                    }
                }
            } else {
                if (isGroupOwner && group != null) {
                    payload["ssid"] = group.networkName
                    payload["password"] = group.passphrase
                }
                channel.invokeMethod("onConnectionEstablished", payload)
            }

            // Complete any pending connect() call.
            pendingConnectCallback?.invoke(true, ipAddress, TRANSFER_PORT)
            pendingConnectCallback = null
        } else {
            Log.d(TAG, "P2P Connection lost")
            channel.invokeMethod("onConnectionLost", null)

            // If we were waiting for a connection, fail it.
            pendingConnectCallback?.invoke(false, null, null)
            pendingConnectCallback = null
        }
    }
    
    fun disconnect() {
        p2pManager?.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group removed successfully")
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to remove group: $reason")
            }
        })
    }
    
    fun cleanup() {
        stopDiscovery()
        disconnect()
        
        // Cleanup network callback
        networkCallback?.let {
             val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
             try {
                connectivityManager.unregisterNetworkCallback(it)
                connectivityManager.bindProcessToNetwork(null)
             } catch(_: Exception){}
        }
        networkCallback = null
        
        pendingConnectCallback = null
        p2pChannel = null
        p2pManager = null
    }
    
    /**
     * Broadcast receiver for WiFi Direct events
     */
    private class WiFiDirectBroadcastReceiver(
        private val manager: WiFiDirectManager
    ) : BroadcastReceiver() {
        
        @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val isEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    Log.d("WiFiDirect", "P2P state changed: enabled=$isEnabled")
                }
                
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    manager.p2pManager?.requestPeers(manager.p2pChannel) { peers ->
                        manager.onPeersAvailable(peers)
                    }
                }
                
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    manager.p2pManager?.requestConnectionInfo(manager.p2pChannel) { info ->
                        manager.p2pManager?.requestGroupInfo(manager.p2pChannel) { group ->
                            manager.onConnectionChanged(info, group)
                        }
                    }
                }
                
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device: WifiP2pDevice? = try {
                        if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(
                                WifiP2pManager.EXTRA_WIFI_P2P_DEVICE,
                                WifiP2pDevice::class.java
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                        }
                    } catch (e: Exception) {
                        null
                    }

                    if (device != null) {
                        manager.thisDeviceAddress = device.deviceAddress
                        manager.thisDeviceName = device.deviceName
                        Log.d(
                            "WiFiDirect",
                            "This device changed: ${device.deviceName} (${device.deviceAddress})"
                        )
                        manager.channel.invokeMethod(
                            "onThisDeviceChanged",
                            mapOf(
                                "id" to device.deviceAddress,
                                "name" to device.deviceName
                            )
                        )
                        
                        // Check if we're now a group owner (fires when group is created)
                        manager.p2pManager?.requestGroupInfo(manager.p2pChannel) { group ->
                            if (group != null && group.isGroupOwner) {
                                Log.d("WiFiDirect", "✓ Group detected: SSID=${group.networkName}, Pass=${group.passphrase}")
                                val payload = mapOf(
                                    "ipAddress" to "192.168.49.1",
                                    "port" to TRANSFER_PORT,
                                    "isGroupOwner" to true,
                                    "ssid" to group.networkName,
                                    "password" to group.passphrase
                                )
                                manager.channel.invokeMethod("onConnectionEstablished", payload)
                            } else {
                                Log.d("WiFiDirect", "No group yet or not GO: group=${group?.networkName}, isGO=${group?.isGroupOwner}")
                            }
                        }
                    } else {
                        Log.d("WiFiDirect", "This device changed (no device extra)")
                    }
                }
            }
        }
    }
}
