package com.omnity.fylooo

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.Executors

// Placeholder for Cronet/Native implementation
class QuicNativePlugin(private val context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val port = call.argument<Int>("port") ?: 0
                startQuicEngine(port)
                result.success(null)
            }
            "sendStreamData" -> {
                val ip = call.argument<String>("ip")
                val port = call.argument<Int>("port")
                val streamId = call.argument<Int>("streamId")
                val data = call.argument<ByteArray>("data")

                if (ip != null && port != null && streamId != null && data != null) {
                    sendData(ip, port, streamId, data)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            }
            "closeConnection" -> {
                result.success(null)
            }
            "stop" -> {
                stopQuicEngine()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startQuicEngine(port: Int) {
        // TODO: Initialize Cronet Engine or Native UDP Socket here
        // val cronetEngine = CronetEngine.Builder(context).build()
        android.util.Log.d("QuicNative", "Starting Native QUIC on port $port")
    }

    private fun sendData(ip: String, port: Int, streamId: Int, data: ByteArray) {
        executor.submit {
            // TODO: Use Cronet UrlRequest or BidirectionalStream
            // For now, this is where the native reliable transport logic goes.
            android.util.Log.d("QuicNative", "Sending ${data.size} bytes to $ip:$port stream $streamId")
        }
    }

    private fun stopQuicEngine() {
        android.util.Log.d("QuicNative", "Stopping Native QUIC")
    }

    companion object {
        fun register(context: Context, channel: MethodChannel): QuicNativePlugin {
            return QuicNativePlugin(context, channel)
        }
    }
}
