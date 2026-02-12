package com.zen.security

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.zen.security.vpn.VpnStatusBroadcaster
import com.zen.security.vpn.ZenVpnService
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.zen.security/vpn"
    private val VPN_STATUS_CHANNEL = "com.zen.security/vpn_status"
    private val VPN_REQUEST_CODE = 1001
    
    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfig: String? = null
    private var pendingServerName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val configMap = call.argument<Map<String, Any>>("config")
                    if (configMap != null) {
                        val config = mapToSingboxConfig(configMap)
                        val serverName = configMap["name"]?.toString() ?: ""
                        startVpn(config, serverName, result)
                    } else {
                        result.error("INVALID_CONFIG", "Config is required", null)
                    }
                }
                "disconnect" -> {
                    stopVpn(result)
                }
                "checkPermission" -> {
                    val intent = VpnService.prepare(this)
                    result.success(intent == null)
                }
                "requestPermission" -> {
                    requestVpnPermission(result)
                }
                "isConnected" -> {
                    result.success(ZenVpnService.isRunning)
                }
                "getLogs" -> {
                    val logsCopy = synchronized(ZenVpnService.logs) {
                        ZenVpnService.logs.toList()
                    }
                    result.success(logsCopy)
                }
                "getLastError" -> {
                    result.success(ZenVpnService.lastError)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_STATUS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                VpnStatusBroadcaster.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                VpnStatusBroadcaster.clearEventSink()
            }
        })
    }

    private fun mapToSingboxConfig(config: Map<String, Any>): String {
        val server = config["server"] as? String ?: ""
        val port = (config["port"] as? Number)?.toInt() ?: 443
        val protocol = config["protocol"] as? String ?: "VLESS"
        val host = config["host"] as? String ?: server
        val dnsUrl = config["dnsUrl"] as? String ?: "https://1.1.1.1/dns-query"

        val json = JSONObject().apply {
            put("log", JSONObject().apply {
                put("level", "warn")
                put("timestamp", true)
            })

            put("dns", JSONObject().apply {
                put("servers", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("tag", "proxy-dns")
                        put("address", dnsUrl)
                        put("address_resolver", "direct-dns")
                        put("detour", "proxy")
                    })
                    put(JSONObject().apply {
                        put("tag", "direct-dns")
                        put("address", "8.8.8.8")
                        put("detour", "direct")
                    })
                })
                put("rules", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("outbound", org.json.JSONArray().apply { put("any") })
                        put("server", "direct-dns")
                    })
                })
                put("final", "proxy-dns")
            })

            put("inbounds", org.json.JSONArray().apply {
                put(JSONObject().apply {
                    put("type", "tun")
                    put("tag", "tun-in")
                    put("address", org.json.JSONArray().apply {
                        put("172.19.0.1/30")
                        put("fdfe:dcba:9876::1/126")
                    })
                    put("mtu", 1500)
                    put("stack", "mixed")
                    put("sniff", true)
                    put("sniff_override_destination", false)
                })
            })

            put("outbounds", org.json.JSONArray().apply {
                // Build proxy outbound based on protocol
                put(buildProxyOutbound(protocol, config, server, port, host))
                put(JSONObject().apply {
                    put("type", "direct")
                    put("tag", "direct")
                })
                put(JSONObject().apply {
                    put("type", "block")
                    put("tag", "block")
                })
                put(JSONObject().apply {
                    put("type", "dns")
                    put("tag", "dns-out")
                })
            })

            put("route", JSONObject().apply {
                put("auto_detect_interface", false)
                put("final", "proxy")
                put("rules", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("protocol", org.json.JSONArray().apply { put("dns") })
                        put("outbound", "dns-out")
                    })
                })
            })
        }

        val configStr = json.toString()
        android.util.Log.d("ZenConfig", "Generated config ($protocol): $configStr")
        return configStr
    }

    private fun buildProxyOutbound(
        protocol: String,
        config: Map<String, Any>,
        server: String,
        port: Int,
        host: String
    ): JSONObject {
        return when (protocol.uppercase()) {
            "HYSTERIA2" -> buildHysteria2Outbound(config, server, port, host)
            else -> buildVlessOutbound(config, server, port, host)
        }
    }

    private fun buildVlessOutbound(
        config: Map<String, Any>,
        server: String,
        port: Int,
        host: String
    ): JSONObject {
        val uuid = config["uuid"] as? String ?: ""
        val path = config["path"] as? String ?: "/"
        val security = config["security"] as? String ?: "tls"
        val transportType = (config["transportType"] as? String ?: "ws").trim()
        val publicKey = config["publicKey"] as? String
        val shortId = config["shortId"] as? String
        val flow = config["flow"] as? String
        val fingerprint = config["fingerprint"] as? String ?: "chrome"
        val sni = config["sni"] as? String ?: host

        return JSONObject().apply {
            put("type", "vless")
            put("tag", "proxy")
            put("server", server)
            put("server_port", port)
            put("uuid", uuid)

            put("tls", JSONObject().apply {
                put("enabled", true)
                put("server_name", sni)
                if (security == "reality") {
                    put("utls", JSONObject().apply {
                        put("enabled", true)
                        put("fingerprint", fingerprint)
                    })
                    put("reality", JSONObject().apply {
                        put("enabled", true)
                        publicKey?.let { put("public_key", it) }
                        shortId?.let { put("short_id", it) }
                    })
                }
            })

            if (!flow.isNullOrEmpty()) {
                put("flow", flow)
            }

            if (security == "tls" && transportType.isNotEmpty() && transportType != "tcp") {
                put("transport", JSONObject().apply {
                    put("type", transportType)
                    when (transportType) {
                        "ws" -> {
                            put("path", path)
                            put("headers", JSONObject().apply {
                                put("Host", sni)
                            })
                        }
                        "grpc" -> {
                            val serviceName = config["serviceName"] as? String ?: "grpc"
                            put("service_name", serviceName)
                        }
                        "h2" -> {
                            put("path", path)
                        }
                    }
                })
            }
        }
    }

    private fun buildHysteria2Outbound(
        config: Map<String, Any>,
        server: String,
        port: Int,
        host: String
    ): JSONObject {
        val password = config["password"] as? String ?: ""
        val sni = config["sni"] as? String ?: host
        val obfsType = config["obfsType"] as? String
        val obfsPassword = config["obfsPassword"] as? String
        val upMbps = (config["upMbps"] as? Number)?.toInt()
        val downMbps = (config["downMbps"] as? Number)?.toInt()
        val insecure = config["insecure"] as? Boolean ?: false

        return JSONObject().apply {
            put("type", "hysteria2")
            put("tag", "proxy")
            put("server", server)
            put("server_port", port)
            put("password", password)

            // Bandwidth limits
            if (upMbps != null && upMbps > 0) {
                put("up_mbps", upMbps)
            }
            if (downMbps != null && downMbps > 0) {
                put("down_mbps", downMbps)
            }

            // Obfuscation (optional)
            if (!obfsType.isNullOrEmpty() && !obfsPassword.isNullOrEmpty()) {
                put("obfs", JSONObject().apply {
                    put("type", obfsType)
                    put("password", obfsPassword)
                })
            }

            // TLS is always required for Hysteria2
            put("tls", JSONObject().apply {
                put("enabled", true)
                put("server_name", sni)
                if (insecure) {
                    put("insecure", true)
                }
            })
        }
    }

    private fun startVpn(config: String, serverName: String, result: MethodChannel.Result) {
        android.util.Log.i("ZenVPN", "startVpn called, config length: ${config.length}")
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            pendingConfig = config
            pendingServerName = serverName
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // Already have permission, start VPN
            try {
                val vpnIntent = Intent(this, ZenVpnService::class.java)
                vpnIntent.putExtra("config", config)
                vpnIntent.putExtra("serverName", serverName)
                startService(vpnIntent)
                result.success(true)
            } catch (e: Exception) {
                android.util.Log.e("ZenVPN", "Failed to start VPN service: ${e.message}", e)
                result.error("VPN_START_FAILED", e.message, null)
            }
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        val intent = Intent(this, ZenVpnService::class.java)
        intent.action = "STOP"
        startService(intent)
        result.success(true)
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                // Permission granted, start VPN if we have pending config
                pendingConfig?.let { config ->
                    val vpnIntent = Intent(this, ZenVpnService::class.java)
                    vpnIntent.putExtra("config", config)
                    vpnIntent.putExtra("serverName", pendingServerName ?: "")
                    startService(vpnIntent)
                }
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
            pendingConfig = null
            pendingServerName = null
        }
    }
}
