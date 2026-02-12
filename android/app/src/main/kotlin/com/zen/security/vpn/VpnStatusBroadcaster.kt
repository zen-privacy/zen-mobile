package com.zen.security.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject

/**
 * Singleton that broadcasts VPN status events to Flutter via EventChannel.
 * All EventSink calls are dispatched to the main (UI) thread as required by Flutter.
 * Status values: disconnected, connecting, connected, disconnecting, reconnecting, error
 */
object VpnStatusBroadcaster {

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun setEventSink(sink: EventChannel.EventSink?) {
        android.util.Log.d("VpnStatusBroadcaster", "setEventSink: ${if (sink != null) "SET (non-null)" else "SET (null)"}")
        eventSink = sink
    }

    fun clearEventSink() {
        android.util.Log.d("VpnStatusBroadcaster", "clearEventSink called")
        eventSink = null
    }

    /**
     * Broadcast status to Flutter on the main thread.
     * @param status One of: disconnected, connecting, connected, disconnecting, reconnecting, error
     * @param details Optional map with "message", "serverName", etc.
     */
    fun broadcastStatus(status: String, details: Map<String, Any?>? = null) {
        val sink = eventSink
        if (sink == null) {
            android.util.Log.w("VpnStatusBroadcaster", "broadcastStatus('$status') — eventSink is NULL, event dropped!")
            return
        }

        val json = JSONObject().apply {
            put("status", status)
            put("message", details?.get("message")?.toString() ?: "")
            put("serverName", details?.get("serverName")?.toString() ?: "")
        }

        val jsonStr = json.toString()
        android.util.Log.d("VpnStatusBroadcaster", "broadcastStatus('$status') posting to main thread: $jsonStr")
        mainHandler.post {
            try {
                sink.success(jsonStr)
                android.util.Log.d("VpnStatusBroadcaster", "broadcastStatus('$status') delivered to Flutter")
            } catch (e: Exception) {
                android.util.Log.e("VpnStatusBroadcaster", "Failed to broadcast: ${e.message}", e)
            }
        }
    }
}
