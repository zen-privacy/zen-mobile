package com.zen.security.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.zen.security.MainActivity
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * Zen VPN Service using libbox (sing-box v1.10+)
 */
class ZenVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        private const val TAG = "ZenVpnService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "zen_vpn_channel"
        private const val MAX_LOGS = 200

        var instance: ZenVpnService? = null
        var isRunning = false
        val logs = mutableListOf<String>()
        var lastError: String? = null

        // Cached formatter — avoid allocation on every log call
        private val logDateFormat = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US)

        fun addLog(level: String, msg: String) {
            val ts = logDateFormat.format(java.util.Date())
            val entry = "[$ts] $level: $msg"
            synchronized(logs) {
                logs.add(entry)
                while (logs.size > MAX_LOGS) logs.removeAt(0)
            }
            android.util.Log.d(TAG, entry)
        }
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var boxService: BoxService? = null
    private var commandServer: CommandServer? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var currentConfig: String = ""
    private var currentServerName: String = ""

    // Auto-reconnect state
    private var reconnectAttempt = 0
    private val maxReconnectAttempts = 5
    private var reconnectJob: Job? = null
    private var userRequestedStop = false
    @Volatile private var isReconnecting = false
    @Volatile private var lastConnectedTimestamp = 0L
    private val RECONNECT_COOLDOWN_MS = 10_000L // Ignore onLost within 10s of (re)connect
    private var onLostDebounceJob: Job? = null


    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP" -> {
                userRequestedStop = true
                reconnectJob?.cancel()
                reconnectJob = null
                stopVpn()
                return START_NOT_STICKY
            }
            else -> {
                val config = intent?.getStringExtra("config")
                if (config != null) {
                    currentConfig = config
                    currentServerName = intent?.getStringExtra("serverName") ?: ""
                    userRequestedStop = false
                    isStopping = false
                    reconnectAttempt = 0
                    startVpn()
                }
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunning) {
            addLog("WARN", "VPN already running, stopping first...")
            // Stop old connection synchronously before starting new one
            try {
                boxService?.close()
                boxService = null
                commandServer?.close()
                commandServer = null
                vpnInterface?.close()
                vpnInterface = null
                isRunning = false
            } catch (e: Exception) {
                addLog("WARN", "Error stopping old VPN: ${e.message}")
            }
        }

        synchronized(logs) { logs.clear() }
        lastError = null

        VpnStatusBroadcaster.broadcastStatus("connecting", mapOf("serverName" to currentServerName))

        scope.launch {
            try {
                addLog("INFO", "Starting VPN service...")
                addLog("INFO", "Config: ${currentConfig.take(1000)}")

                val notification = createNotification(currentServerName)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                addLog("INFO", "Foreground service started")

                val workDir = filesDir.absolutePath
                val tempDir = cacheDir.absolutePath
                addLog("INFO", "Libbox.setup($workDir, $tempDir)")
                Libbox.setup(workDir, tempDir, tempDir, false)
                addLog("INFO", "Libbox setup OK")

                addLog("INFO", "Creating box service...")
                boxService = Libbox.newService(currentConfig, this@ZenVpnService)
                addLog("INFO", "Box service created OK")

                addLog("INFO", "Starting command server...")
                commandServer = Libbox.newCommandServer(this@ZenVpnService, 50)
                commandServer?.start()
                addLog("INFO", "Command server started OK")

                addLog("INFO", "Starting box service (sing-box)...")
                boxService?.start()
                addLog("INFO", "Box service started OK!")

                isRunning = true
                lastConnectedTimestamp = System.currentTimeMillis()
                addLog("INFO", "VPN CONNECTED successfully")
                VpnStatusBroadcaster.broadcastStatus("connected", mapOf("serverName" to currentServerName))


            } catch (e: Exception) {
                val err = "FAILED: ${e.javaClass.simpleName}: ${e.message}"
                addLog("ERROR", err)
                VpnStatusBroadcaster.broadcastStatus("error", mapOf("message" to err, "serverName" to currentServerName))
                addLog("ERROR", "Stack: ${e.stackTraceToString().take(500)}")
                lastError = err
                stopVpn()
            }
        }
    }

    @Volatile private var isStopping = false

    private fun stopVpn() {
        // Guard against double-stop: onDestroy() calls stopVpn() again after stopSelf()
        if (isStopping) return
        isStopping = true

        VpnStatusBroadcaster.broadcastStatus("disconnecting", mapOf("serverName" to currentServerName))

        scope.launch {
            try {
                boxService?.close()
                boxService = null

                commandServer?.close()
                commandServer = null

                vpnInterface?.close()
                vpnInterface = null

                isRunning = false

                VpnStatusBroadcaster.broadcastStatus("disconnected", mapOf("serverName" to currentServerName))

                Log.i(TAG, "VPN stopped")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping VPN: ${e.message}", e)
            }
        }
    }

    override fun onDestroy() {
        stopVpn() // guarded by isStopping flag
        scope.cancel()
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        userRequestedStop = true
        stopVpn()
        super.onRevoke()
    }

    /**
     * Auto-reconnect with exponential backoff (2s, 4s, 8s, 16s, 30s).
     * Max 5 attempts. Called when connection drops unexpectedly.
     * Guards: cooldown period after connect, isReconnecting flag.
     */
    private fun scheduleReconnect() {
        if (userRequestedStop) {
            addLog("INFO", "Reconnect skipped — user requested stop")
            return
        }
        if (isReconnecting) {
            addLog("INFO", "Reconnect skipped — already reconnecting")
            return
        }

        // Cooldown: ignore onLost within N seconds of last successful (re)connect.
        // This prevents the self-triggered loop where closing/reopening the box service
        // causes a transient onLost on the new NetworkCallback.
        val sinceLastConnect = System.currentTimeMillis() - lastConnectedTimestamp
        if (sinceLastConnect < RECONNECT_COOLDOWN_MS) {
            addLog("INFO", "Reconnect skipped — cooldown (${sinceLastConnect}ms < ${RECONNECT_COOLDOWN_MS}ms since last connect)")
            return
        }

        if (reconnectAttempt >= maxReconnectAttempts) {
            addLog("WARN", "Max reconnect attempts reached ($maxReconnectAttempts)")
            VpnStatusBroadcaster.broadcastStatus("error", mapOf(
                "message" to "Connection lost after $maxReconnectAttempts retries",
                "serverName" to currentServerName
            ))
            return
        }

        reconnectAttempt++
        val delayMs = (2000L * (1 shl (reconnectAttempt - 1))).coerceAtMost(30_000L) // 2s, 4s, 8s, 16s capped at 30s
        addLog("INFO", "Scheduling reconnect attempt $reconnectAttempt/$maxReconnectAttempts in ${delayMs}ms")

        VpnStatusBroadcaster.broadcastStatus("reconnecting", mapOf(
            "message" to "Attempt $reconnectAttempt/$maxReconnectAttempts",
            "serverName" to currentServerName
        ))

        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(delayMs)
            if (isActive && !userRequestedStop) {
                doReconnect()
            }
        }
    }

    private fun doReconnect() {
        isReconnecting = true
        scope.launch {
            try {
                addLog("INFO", "Reconnect attempt $reconnectAttempt/$maxReconnectAttempts — executing")

                // Close existing resources
                boxService?.close()
                boxService = null
                commandServer?.close()
                commandServer = null
                vpnInterface?.close()
                vpnInterface = null
                isRunning = false

                // Re-create and start
                boxService = Libbox.newService(currentConfig, this@ZenVpnService)
                commandServer = Libbox.newCommandServer(this@ZenVpnService, 50)
                commandServer?.start()
                boxService?.start()

                isRunning = true
                isReconnecting = false
                reconnectAttempt = 0 // Reset on success
                lastConnectedTimestamp = System.currentTimeMillis() // Reset cooldown
                addLog("INFO", "Reconnect successful!")
                VpnStatusBroadcaster.broadcastStatus("connected", mapOf("serverName" to currentServerName))
                updateNotification()
            } catch (e: Exception) {
                isReconnecting = false
                addLog("ERROR", "Reconnect failed: ${e.message}")
                scheduleReconnect() // Try again with next attempt
            }
        }
    }

    // PlatformInterface implementation for libbox v1.10+

    override fun openTun(options: TunOptions): Int {
        addLog("INFO", "openTun called! MTU=${options.mtu}")
        val builder = Builder()
            .setSession("Zen Privacy")
            .setMtu(options.mtu)

        // Add IPv4 addresses from sing-box config
        var hasInet4Address = false
        val inet4Iterator = options.getInet4Address()
        while (inet4Iterator.hasNext()) {
            val addr = inet4Iterator.next()
            addLog("INFO", "TUN IPv4 address: ${addr.address()}/${addr.prefix()}")
            builder.addAddress(addr.address(), addr.prefix())
            hasInet4Address = true
        }

        // Add IPv6 addresses from sing-box config
        var hasInet6Address = false
        val inet6Iterator = options.getInet6Address()
        while (inet6Iterator.hasNext()) {
            val addr = inet6Iterator.next()
            addLog("INFO", "TUN IPv6 address: ${addr.address()}/${addr.prefix()}")
            builder.addAddress(addr.address(), addr.prefix())
            hasInet6Address = true
        }

        // Add IPv4 routes — use provided or default to all traffic
        var hasInet4Route = false
        val inet4RouteIterator = options.getInet4RouteAddress()
        while (inet4RouteIterator.hasNext()) {
            val route = inet4RouteIterator.next()
            addLog("INFO", "TUN IPv4 route: ${route.address()}/${route.prefix()}")
            builder.addRoute(route.address(), route.prefix())
            hasInet4Route = true
        }
        if (!hasInet4Route && hasInet4Address) {
            addLog("INFO", "No IPv4 routes from sing-box, adding default 0.0.0.0/0")
            builder.addRoute("0.0.0.0", 0)
        }

        // Add IPv6 routes — use provided or default to all traffic
        var hasInet6Route = false
        val inet6RouteIterator = options.getInet6RouteAddress()
        while (inet6RouteIterator.hasNext()) {
            val route = inet6RouteIterator.next()
            addLog("INFO", "TUN IPv6 route: ${route.address()}/${route.prefix()}")
            builder.addRoute(route.address(), route.prefix())
            hasInet6Route = true
        }
        if (!hasInet6Route && hasInet6Address) {
            addLog("INFO", "No IPv6 routes from sing-box, adding default ::/0")
            builder.addRoute("::", 0)
        }

        // Add DNS servers from sing-box or use fallback
        var hasDns = false
        try {
            val dnsAddresses = options.getDNSServerAddress()
            for (dns in dnsAddresses.split(",")) {
                val trimmed = dns.trim()
                if (trimmed.isNotEmpty()) {
                    addLog("INFO", "TUN DNS: $trimmed")
                    builder.addDnsServer(trimmed)
                    hasDns = true
                }
            }
        } catch (e: Exception) {
            addLog("WARN", "Failed to get DNS from options: ${e.message}")
        }
        if (!hasDns) {
            addLog("INFO", "No DNS from sing-box, using fallback 1.1.1.1")
            builder.addDnsServer("1.1.1.1")
        }

        // Exclude our app to prevent routing loops
        try {
            builder.addDisallowedApplication(packageName)
            addLog("INFO", "Excluded $packageName from VPN")
        } catch (e: Exception) {
            addLog("WARN", "Failed to exclude app: ${e.message}")
        }

        vpnInterface = builder.establish()
        val fd = vpnInterface?.fd ?: -1
        addLog("INFO", "TUN established, fd=$fd")
        return fd
    }

    override fun writeLog(message: String) {
        addLog("BOX", message)
    }

    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int
    ): Int = -1

    override fun packageNameByUid(uid: Int): String = ""

    override fun uidByPackageName(packageName: String): Int = -1

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformDefaultInterfaceMonitor(): Boolean = true

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        addLog("INFO", "Starting platform default interface monitor")
        val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

        val callback = object : ConnectivityManager.NetworkCallback() {
            private fun notifyInterfaceUpdate(network: Network) {
                try {
                    val linkProperties = connectivityManager.getLinkProperties(network)
                    val interfaceName = linkProperties?.interfaceName ?: ""
                    // Network handle serves as interface index on Android
                    val interfaceIndex = network.hashCode()
                    addLog("INFO", "Interface update: name=$interfaceName index=$interfaceIndex")
                    listener.updateDefaultInterface(interfaceName, interfaceIndex)
                } catch (e: Exception) {
                    addLog("WARN", "updateDefaultInterface error: ${e.message}")
                }
            }

            override fun onAvailable(network: Network) {
                addLog("INFO", "Network available: $network")
                notifyInterfaceUpdate(network)
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                notifyInterfaceUpdate(network)
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) {
                notifyInterfaceUpdate(network)
            }

            override fun onLost(network: Network) {
                addLog("INFO", "Network lost: $network")
                try {
                    listener.updateDefaultInterface("", 0)
                } catch (e: Exception) {
                    addLog("WARN", "updateDefaultInterface error: ${e.message}")
                }
                // Debounce: wait 3s to see if a new network appears before reconnecting.
                // This avoids self-triggered loops when the VPN closes/reopens its TUN interface.
                if (isRunning && !userRequestedStop && !isReconnecting) {
                    onLostDebounceJob?.cancel()
                    onLostDebounceJob = scope.launch {
                        addLog("INFO", "Network lost — debouncing 3s before reconnect decision")
                        delay(3000)
                        // Re-check: if still running and not already reconnecting
                        if (isRunning && !userRequestedStop && !isReconnecting) {
                            addLog("INFO", "Network still lost after debounce, scheduling reconnect")
                            scheduleReconnect()
                        } else {
                            addLog("INFO", "Network recovered or VPN stopped during debounce, skipping reconnect")
                        }
                    }
                }
            }
        }
        networkCallback = callback

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        connectivityManager.registerNetworkCallback(request, callback)

        // Report current default network immediately
        val activeNetwork = connectivityManager.activeNetwork
        if (activeNetwork != null) {
            val linkProperties = connectivityManager.getLinkProperties(activeNetwork)
            val interfaceName = linkProperties?.interfaceName ?: ""
            val interfaceIndex = activeNetwork.hashCode()
            addLog("INFO", "Initial interface: name=$interfaceName index=$interfaceIndex")
            listener.updateDefaultInterface(interfaceName, interfaceIndex)
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        addLog("INFO", "Closing platform default interface monitor")
        networkCallback?.let {
            try {
                val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                connectivityManager.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                addLog("WARN", "Failed to unregister network callback: ${e.message}")
            }
        }
        networkCallback = null
    }

    override fun usePlatformInterfaceGetter(): Boolean = false

    override fun getInterfaces(): NetworkInterfaceIterator? = null

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {}

    override fun readWIFIState(): io.nekohasekai.libbox.WIFIState? = null

    // CommandServerHandler implementation

    override fun serviceReload() {
        // Reload service if needed
    }

    override fun getSystemProxyStatus(): io.nekohasekai.libbox.SystemProxyStatus? = null

    override fun setSystemProxyEnabled(enabled: Boolean) {}

    override fun postServiceClose() {
        stopVpn()
    }

    // Notification

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Zen Privacy VPN connection status"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(serverName: String? = null): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Disconnect action
        val stopIntent = Intent(this, ZenVpnService::class.java).apply {
            action = "STOP"
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val displayName = if (!serverName.isNullOrEmpty()) serverName else "VPN"
        val disconnectAction = Notification.Action.Builder(
            null, "Disconnect", stopPendingIntent
        ).build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }.apply {
            setContentTitle("Zen Privacy")
            setContentText("Connected to $displayName")
            setSmallIcon(android.R.drawable.ic_lock_lock)
            setContentIntent(openPendingIntent)
            setOngoing(true)
            addAction(disconnectAction)
        }.build()
    }

    private fun updateNotification() {
        val notification = createNotification(currentServerName)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

}
