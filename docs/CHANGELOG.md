# Changelog

## [1.1.0] — 2026-02-12

### Fixed
- **Infinite "connecting"** — EventChannel events now dispatched on main thread via Handler(Looper.getMainLooper())
- **Infinite reconnecting** — Added 10s cooldown after connect + 3s debounce on onLost + isReconnecting guard
- **Infinite "disconnecting"** — Added isStopping flag to prevent double stopVpn() from onDestroy()

### Changed
- **AliDNS added** — New DNS provider option (dns.alidns.com) in settings
- **sing-box log level** — Changed from "debug" to "warn" (reduces memory ~30-50 MB from Go string allocations)
- **MAX_LOGS reduced** — 500 → 200 entries (less memory for in-memory log buffer)
- **Log polling interval** — 1s → 3s when log panel is open (reduces platform channel overhead)
- **SimpleDateFormat cached** — Was creating new instance per addLog() call, now reused

### Removed
- **Traffic stats feature** — sing-box CommandClient StatusMessage always reported zeros; removed CommandClient, StatusCard download/upload rows, stats polling timer, getTrafficStats handler

## [1.0.0] — 2026-02-12

### Added
- **VLESS+REALITY support** — Full parsing of VLESS REALITY links (pbk, sid, flow, fingerprint, uTLS)
- **Hysteria2 support** — Full Hysteria2 protocol with obfuscation, bandwidth limits, TLS
- **Subscription service** — Load servers from subscription URL (base64 + plain text), auto-refresh, usage tracking with progress bar
- **Honest connection status** — Real-time VPN status via EventChannel (connecting/connected/disconnecting/reconnecting/error)
- **Auto-reconnect** — Exponential backoff (2s→30s, max 5 retries) on network loss
- **Server ping** — TCP connect latency with color-coded badges (green <100ms, yellow <300ms, red >=300ms)
- **Settings screen** — DNS provider presets (Cloudflare, Google, Quad9, AdGuard, AliDNS, Custom DoH), auto-connect toggle, kill switch toggle
- **Notification with Disconnect** — Persistent notification showing server name with Disconnect action button
- **Protocol labels** — UI shows VLESS/WS, VLESS/REALITY, HY2 tags on server cards

### Fixed
- TUN traffic now properly routes through VPN (removed auto_route/strict_route, added explicit routes)
- Platform default interface monitor using ConnectivityManager instead of banned netlink sockets
