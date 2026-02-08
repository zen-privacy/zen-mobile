package com.zen.security.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
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

        var instance: ZenVpnService? = null
        var isRunning = false
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var boxService: BoxService? = null
    private var commandServer: CommandServer? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var currentConfig: String = ""

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP" -> {
                stopVpn()
                return START_NOT_STICKY
            }
            else -> {
                val config = intent?.getStringExtra("config")
                if (config != null) {
                    currentConfig = config
                    startVpn()
                }
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunning) {
            Log.w(TAG, "VPN already running")
            return
        }

        scope.launch {
            try {
                Log.i(TAG, "Starting VPN service...")
                Log.i(TAG, "Config: ${currentConfig.take(500)}")

                // Start foreground service
                startForeground(NOTIFICATION_ID, createNotification())
                Log.i(TAG, "Foreground service started")

                // Initialize libbox
                val workDir = filesDir.absolutePath
                val tempDir = cacheDir.absolutePath
                Log.i(TAG, "Libbox setup: workDir=$workDir, tempDir=$tempDir")
                Libbox.setup(workDir, tempDir, tempDir, false)
                Log.i(TAG, "Libbox setup done")

                // Create box service with config
                Log.i(TAG, "Creating box service...")
                boxService = Libbox.newService(currentConfig, this@ZenVpnService)
                Log.i(TAG, "Box service created")

                // Start command server for traffic stats
                Log.i(TAG, "Starting command server...")
                commandServer = Libbox.newCommandServer(this@ZenVpnService, 50)
                commandServer?.start()
                Log.i(TAG, "Command server started")

                // Start the box service
                Log.i(TAG, "Starting box service...")
                boxService?.start()
                Log.i(TAG, "Box service started!")

                isRunning = true
                Log.i(TAG, "VPN started successfully with libbox")

            } catch (e: Exception) {
                Log.e(TAG, "Failed to start VPN: ${e.message}", e)
                Log.e(TAG, "Stack trace:", e)
                stopVpn()
            }
        }
    }

    private fun stopVpn() {
        scope.launch {
            try {
                boxService?.close()
                boxService = null

                commandServer?.close()
                commandServer = null

                vpnInterface?.close()
                vpnInterface = null

                isRunning = false

                Log.i(TAG, "VPN stopped")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping VPN: ${e.message}", e)
            }
        }
    }

    override fun onDestroy() {
        stopVpn()
        scope.cancel()
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    // PlatformInterface implementation for libbox v1.10+

    override fun openTun(options: TunOptions): Int {
        Log.i(TAG, "openTun called! MTU=${options.mtu}")
        val builder = Builder()
            .setSession("Zen Privacy")
            .setMtu(options.mtu)

        // Add IPv4 addresses using iterator
        val inet4Iterator = options.getInet4Address()
        while (inet4Iterator.hasNext()) {
            val addr = inet4Iterator.next()
            builder.addAddress(addr.address(), addr.prefix())
        }

        // Add IPv6 addresses using iterator
        val inet6Iterator = options.getInet6Address()
        while (inet6Iterator.hasNext()) {
            val addr = inet6Iterator.next()
            builder.addAddress(addr.address(), addr.prefix())
        }

        // Add IPv4 routes using iterator
        val inet4RouteIterator = options.getInet4RouteAddress()
        while (inet4RouteIterator.hasNext()) {
            val route = inet4RouteIterator.next()
            builder.addRoute(route.address(), route.prefix())
        }

        // Add IPv6 routes using iterator
        val inet6RouteIterator = options.getInet6RouteAddress()
        while (inet6RouteIterator.hasNext()) {
            val route = inet6RouteIterator.next()
            builder.addRoute(route.address(), route.prefix())
        }

        // Add DNS server (returns comma-separated string)
        try {
            val dnsAddresses = options.getDNSServerAddress()
            for (dns in dnsAddresses.split(",")) {
                val trimmed = dns.trim()
                if (trimmed.isNotEmpty()) {
                    builder.addDnsServer(trimmed)
                }
            }
        } catch (e: Exception) {
            builder.addDnsServer("1.1.1.1")
        }

        // Exclude our app to prevent loops
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to exclude app: ${e.message}")
        }

        vpnInterface = builder.establish()
        val fd = vpnInterface?.fd ?: -1
        Log.i(TAG, "TUN established, fd=$fd")
        return fd
    }

    override fun writeLog(message: String) {
        Log.i(TAG, message)
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

    override fun usePlatformDefaultInterfaceMonitor(): Boolean = false

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        // Not implemented - using platform auto detect
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        // Not implemented - using platform auto detect
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

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }.apply {
            setContentTitle("Zen Privacy")
            setContentText("VPN Connected")
            setSmallIcon(android.R.drawable.ic_lock_lock)
            setContentIntent(pendingIntent)
            setOngoing(true)
        }.build()
    }

    // Traffic stats (BoxService doesn't expose status directly)
    fun getTrafficStats(): Map<String, Long> {
        return mapOf("rx" to 0L, "tx" to 0L)
    }
}
