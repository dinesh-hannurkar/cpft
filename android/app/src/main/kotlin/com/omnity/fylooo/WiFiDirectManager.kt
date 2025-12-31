package com.omnity.fylooo

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
import io.flutter.plugin.common.MethodChannel

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
            
            channel.invokeMethod("onConnectionEstablished", mapOf(
                "ipAddress" to ipAddress,
                "port" to TRANSFER_PORT,
                "isGroupOwner" to isGroupOwner
            ))

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
                    } else {
                        Log.d("WiFiDirect", "This device changed (no device extra)")
                    }
                }
            }
        }
    }
}
