package com.zen.security

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.zen.security.vpn.ZenVpnService
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.zen.security/vpn"
    private val VPN_REQUEST_CODE = 1001
    
    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfig: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val configMap = call.argument<Map<String, Any>>("config")
                    if (configMap != null) {
                        val config = mapToSingboxConfig(configMap)
                        startVpn(config, result)
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
                "getTrafficStats" -> {
                    val stats = ZenVpnService.instance?.getTrafficStats() 
                        ?: mapOf("rx" to 0L, "tx" to 0L)
                    result.success(stats)
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
    }

    private fun mapToSingboxConfig(config: Map<String, Any>): String {
        val server = config["server"] as? String ?: ""
        val port = (config["port"] as? Number)?.toInt() ?: 443
        val uuid = config["uuid"] as? String ?: ""
        val host = config["host"] as? String ?: server
        val path = config["path"] as? String ?: "/"

        val json = JSONObject().apply {
            put("log", JSONObject().apply {
                put("level", "debug")
                put("timestamp", true)
            })

            put("dns", JSONObject().apply {
                put("servers", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("tag", "proxy-dns")
                        put("address", "https://1.1.1.1/dns-query")
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
                    put("mtu", 9000)
                    put("stack", "mixed")
                    put("sniff", true)
                    put("sniff_override_destination", false)
                })
            })

            put("outbounds", org.json.JSONArray().apply {
                put(JSONObject().apply {
                    put("type", "vless")
                    put("tag", "proxy")
                    put("server", server)
                    put("server_port", port)
                    put("uuid", uuid)
                    put("tls", JSONObject().apply {
                        put("enabled", true)
                        put("server_name", host)
                    })
                    put("transport", JSONObject().apply {
                        put("type", "ws")
                        put("path", path)
                        put("headers", JSONObject().apply {
                            put("Host", host)
                        })
                    })
                })
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
                    put(JSONObject().apply {
                        put("ip_is_private", true)
                        put("outbound", "direct")
                    })
                })
            })
        }

        val configStr = json.toString()
        android.util.Log.d("ZenConfig", "Generated config: $configStr")
        return configStr
    }

    private fun startVpn(config: String, result: MethodChannel.Result) {
        android.util.Log.i("ZenVPN", "startVpn called, config length: ${config.length}")
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            pendingConfig = config
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // Already have permission, start VPN
            try {
                val vpnIntent = Intent(this, ZenVpnService::class.java)
                vpnIntent.putExtra("config", config)
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
                    startService(vpnIntent)
                }
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
            pendingConfig = null
        }
    }
}
