# Architecture

## Overview
Zen Privacy Mobile is a Flutter VPN client for Android that uses libbox (sing-box v1.10+) as the underlying proxy engine. The app supports VLESS (WS+TLS, REALITY), and Hysteria2 protocols via a native Android VPN service.

## Architecture Diagram
```
┌─────────────────────────────────────┐
│           Flutter (Dart)            │
│                                     │
│  HomeScreen ←→ SettingsScreen       │
│      ↓                              │
│  VpnService  PingService            │
│  SubscriptionService  SettingsService│
│      ↓ (MethodChannel + EventChannel)│
├─────────────────────────────────────┤
│         Native Android (Kotlin)     │
│                                     │
│  MainActivity                       │
│    ├── MethodChannel handler        │
│    ├── EventChannel (VPN status)    │
│    └── mapToSingboxConfig()         │
│                                     │
│  ZenVpnService (VpnService)        │
│    ├── PlatformInterface (libbox)   │
│    ├── CommandServerHandler         │
│    ├── CommandClient (stats)        │
│    ├── VpnStatusBroadcaster         │
│    ├── NetworkCallback (reconnect)  │
│    └── Notification (disconnect)    │
│                                     │
│  libbox (sing-box native library)   │
│    ├── BoxService                   │
│    ├── CommandServer/Client         │
│    └── TUN interface management     │
└─────────────────────────────────────┘
```

## Layers

### Presentation (Flutter)
- `lib/screens/home_screen.dart` — Main UI with connection panel, servers, logs
- `lib/screens/settings_screen.dart` — Settings (DNS, connection, subscription, about)
- `lib/widgets/` — StatusCard, ServerCard (with latency), MaskButton

### Application (Flutter Services)
- `lib/services/vpn_service.dart` — VPN connection management, MethodChannel + EventChannel bridge
- `lib/services/subscription_service.dart` — HTTP subscription fetching, base64 parsing, auto-refresh
- `lib/services/ping_service.dart` — TCP connect latency measurement
- `lib/services/settings_service.dart` — SharedPreferences wrapper

### Domain (Models)
- `lib/models/server_profile.dart` — Server profile with VLESS/REALITY/Hysteria2 fields, link parsing
- `lib/models/subscription.dart` — Subscription metadata and usage info

### Infrastructure (Native Android)
- `MainActivity.kt` — Flutter engine bridge, sing-box config generation
- `ZenVpnService.kt` — Android VpnService, libbox integration, TUN management
- `VpnStatusBroadcaster.kt` — Singleton EventChannel broadcaster

## Key Decisions

| Decision | Justification | Date |
|----------|--------------|------|
| libbox (sing-box) as VPN engine | Universal proxy platform, supports all required protocols | 2025 |
| Platform default interface monitor | Android bans netlink sockets for non-root; use ConnectivityManager | 2026-02-12 |
| Explicit route addition in openTun | sing-box doesn't add routes when auto_route is disabled | 2026-02-12 |
| CommandClient for traffic stats | StatusMessage provides real-time uplink/downlink from sing-box | 2026-02-12 |
| EventChannel for VPN status | Reliable native→Dart streaming vs polling | 2026-02-12 |
| TCP connect for ping | Works without special permissions, measures actual connection latency | 2026-02-12 |
| Base64 subscription parsing | Standard format used by all VPN providers | 2026-02-12 |

## Dependencies
- **libbox (sing-box)** — Core VPN/proxy engine
- **Flutter** — Cross-platform UI framework
- **shared_preferences** — Local settings storage
- **flutter_local_notifications** — Notification management
