# Zen Privacy Mobile — 11 Features Implementation Plan

## Context
Приложение Zen Privacy Mobile — Flutter VPN-клиент с libbox (sing-box v1.10). Сейчас это MVP: одна screen, ручной ввод VLESS-ссылок (только WS+TLS), нет настроек, статистика нули, статус врёт. Нужно добавить 11 фич чтобы сделать приложение полноценным.

## 5 Phases, 11 Features

### Phase 1: Protocol + Subscriptions (Features 2, 1)
Без этого ничего не работает — нужно парсить все протоколы и загружать серверы по подписке.

**Feature 2: REALITY + Hysteria2 поддержка**
- `lib/models/server_profile.dart` — добавить поля: `security`, `transportType`, `sni`, `publicKey`, `shortId`, `flow`, `fingerprint`. Переделать `fromVlessLink()` → `fromShareLink()` с поддержкой `vless://` (WS+TLS и REALITY) + `hysteria2://`
- `lib/services/vpn_service.dart` — передавать все новые поля через MethodChannel
- `android/.../MainActivity.kt` — переписать `mapToSingboxConfig()`: три ветки генерации outbound (WS+TLS, REALITY, Hysteria2)
- `lib/widgets/server_card.dart` — показывать тип протокола (VLESS/WS, VLESS/REALITY, HY2)

**Feature 1: Подписка по URL**
- Создать `lib/services/subscription_service.dart` — HTTP GET подписки, парсинг base64, headers (Profile-Update-Interval, Subscription-Userinfo), авто-обновление по таймеру
- Создать `lib/models/subscription.dart` — модель подписки (url, password, usage, refresh interval)
- `lib/screens/home_screen.dart` — новый UI: поле "Add Subscription URL" как основной способ, показ data usage (progress bar), ручные ссылки свернуты

### Phase 2: Connection Reliability (Features 3, 4, 6)

**Feature 3: Честный статус подключения**
- Создать `android/.../vpn/VpnStatusBroadcaster.kt` — singleton EventSink для стриминга статуса
- `android/.../MainActivity.kt` — добавить EventChannel `com.zen.security/vpn_status`
- `android/.../vpn/ZenVpnService.kt` — emit connected/disconnected/error/connecting через broadcaster
- `lib/services/vpn_service.dart` — слушать EventChannel вместо result.success()
- `lib/screens/home_screen.dart` — UI реагирует на реальный статус

**Feature 4: Auto-reconnect**
- `android/.../vpn/ZenVpnService.kt` — ConnectivityManager.NetworkCallback + экспоненциальный backoff (1s → 30s, max 5 попыток), emit reconnecting status
- `lib/screens/home_screen.dart` — показывать "RECONNECTING (2/5)..."

**Feature 6: Рабочая статистика трафика**
- `android/.../vpn/ZenVpnService.kt` — создать CommandClient с CommandClientHandler.writeStatus() для получения uplinkTotal/downlinkTotal от sing-box
- Dart-сторона уже готова (поллинг каждую секунду + StatusCard)

### Phase 3: User Experience (Features 5, 7, 8)

**Feature 5: Пинг серверов**
- Создать `lib/services/ping_service.dart` — TCP connect latency (Socket.connect + Stopwatch)
- `lib/widgets/server_card.dart` — показывать latency: зелёный <100ms, жёлтый <300ms, красный >=300ms
- `lib/screens/home_screen.dart` — pingAll() после загрузки серверов

**Feature 7: Экран настроек**
- Создать `lib/screens/settings_screen.dart` — секции: Connection (auto-connect, kill switch), DNS (preset + custom + DoH), Subscription (refresh interval), About
- Создать `lib/services/settings_service.dart` — SharedPreferences wrapper
- `lib/screens/home_screen.dart` — иконка settings в header
- `android/.../MainActivity.kt` — читать DNS из config map

**Feature 8: Уведомление с кнопкой Disconnect**
- `android/.../vpn/ZenVpnService.kt` — addAction с PendingIntent.getService(STOP), показывать имя сервера

### Phase 4: Security (Features 9, 10)

**Feature 9: Kill Switch**
- `android/.../MainActivity.kt` — передавать killSwitch в config → `strict_route: true`
- `android/.../vpn/ZenVpnService.kt` — не закрывать TUN при unexpected disconnect если kill switch on
- `lib/services/vpn_service.dart` — `openVpnSettings()` для Android Always-on VPN
- `lib/screens/settings_screen.dart` — toggle + кнопка "Configure Always-on VPN"

**Feature 10: Split Tunneling**
- Создать `lib/screens/split_tunnel_screen.dart` — список установленных приложений с toggle, режимы Include/Exclude
- Создать `lib/services/app_list_service.dart` — MethodChannel для получения списка приложений
- `android/.../MainActivity.kt` — handler getInstalledApps
- `android/.../vpn/ZenVpnService.kt` — в openTun() применять addAllowedApplication/addDisallowedApplication
- `android/.../AndroidManifest.xml` — QUERY_ALL_PACKAGES permission

### Phase 5: Widget (Feature 11)

**Feature 11: Home Screen Widget**
- Создать `android/.../widget/VpnWidget.kt` — AppWidgetProvider
- Создать `android/.../widget/VpnWidgetReceiver.kt` — BroadcastReceiver для toggle
- Создать `android/.../res/layout/widget_vpn.xml` — layout
- Создать `android/.../res/xml/widget_info.xml` — metadata
- `android/.../AndroidManifest.xml` — register widget + receiver
- `android/.../vpn/ZenVpnService.kt` — broadcast widget update при смене статуса

## File Summary

**Новые файлы (14):**
- `lib/services/subscription_service.dart`
- `lib/models/subscription.dart`
- `lib/services/ping_service.dart`
- `lib/screens/settings_screen.dart`
- `lib/services/settings_service.dart`
- `lib/screens/split_tunnel_screen.dart`
- `lib/services/app_list_service.dart`
- `android/.../vpn/VpnStatusBroadcaster.kt`
- `android/.../widget/VpnWidget.kt`
- `android/.../widget/VpnWidgetReceiver.kt`
- `android/.../res/layout/widget_vpn.xml`
- `android/.../res/xml/widget_info.xml`

**Модифицируемые файлы (10):**
- `lib/models/server_profile.dart` — Phase 1
- `lib/services/vpn_service.dart` — Phase 1-4
- `lib/screens/home_screen.dart` — Phase 1-3
- `lib/widgets/server_card.dart` — Phase 1, 3
- `lib/widgets/status_card.dart` — Phase 2
- `lib/theme/app_theme.dart` — Phase 3
- `lib/main.dart` — Phase 3
- `android/.../MainActivity.kt` — Phase 1-4
- `android/.../vpn/ZenVpnService.kt` — Phase 2-5
- `android/.../AndroidManifest.xml` — Phase 4-5

## Verification
После каждой фазы: `flutter build apk --release`, тег, проверка на телефоне. Логи в UI покажут ошибки.
