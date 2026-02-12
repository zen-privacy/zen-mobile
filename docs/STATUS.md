# Project Status

## Last Updated
2026-02-12 (evening)

## Current Phase
Development — Stabilization & optimization pass, Phase 4 pending

## In Progress
- [ ] Kill Switch implementation — Phase 4
- [ ] Split Tunneling — Phase 4
- [ ] Home Screen Widget — Phase 5

## Recently Completed
- [x] Feature 1: Subscription by URL (HTTP GET, base64 decode, auto-refresh, usage bar)
- [x] Feature 2: VLESS+REALITY + Hysteria2 support (parser + sing-box config)
- [x] Feature 3: Honest connection status via EventChannel (native -> Dart)
- [x] Feature 4: Auto-reconnect with exponential backoff (2s-30s, max 5 retries, cooldown + debounce)
- [x] Feature 5: Server ping (TCP connect latency, color-coded badges)
- [x] Feature 7: Settings screen (DNS presets incl. AliDNS, auto-connect, kill switch toggle, about)
- [x] Feature 8: Notification with Disconnect button + server name
- [x] Bug fix: Infinite "connecting" — EventChannel events must be dispatched on UI thread
- [x] Bug fix: Infinite reconnecting — added 10s cooldown + 3s debounce on onLost
- [x] Bug fix: Infinite "disconnecting" — added isStopping guard against double stopVpn()
- [x] Removed non-functional traffic stats feature (CommandClient always returned zeros)
- [x] Memory optimization pass:
  - sing-box log level debug -> warn (reduces Go runtime string allocations)
  - Cached SimpleDateFormat (was allocating new instance per log entry)
  - MAX_LOGS 500 -> 200
  - Log panel polling 1s -> 3s
  - Removed dead getTrafficStats code

## Next Steps
1. Feature 9: Kill Switch (strict_route, Always-on VPN guidance)
2. Feature 10: Split Tunneling (per-app VPN routing)
3. Feature 11: Home Screen Widget (Android AppWidgetProvider)
4. Kotlin version upgrade to 2.1.0+

## Blocking Factors / Issues
- Kotlin 1.9.24 will soon lose Flutter support — upgrade to 2.1.0+ needed
- Kill Switch requires testing with strict_route on Android (netlink restrictions)
- sing-box Go runtime consumes ~220 MB (unavoidable — Go GC heap + mmap regions)

## Notes for the next session
- All Phase 1-3 features are implemented and stable
- Traffic stats feature was removed — sing-box CommandClient StatusMessage always reported zeros
- REALITY config uses `utls` + `reality` blocks inside `tls`, no transport block needed
- Memory profile: ~320 MB PSS, ~220 MB from Go runtime (libbox), ~12 MB Graphics, ~11 MB Java Heap
- CPU: 0% at idle — no background work when connected
- Reconnect has 3-layer protection: isReconnecting flag, 10s cooldown, 3s debounce
- Disconnect has isStopping guard against double-call from onDestroy()
