import 'package:shared_preferences/shared_preferences.dart';

/// Centralized settings management using SharedPreferences.
class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Connection Settings ---

  /// Auto-connect on app launch
  bool get autoConnect => _prefs?.getBool('autoConnect') ?? false;
  Future<void> setAutoConnect(bool value) async {
    await init();
    await _prefs!.setBool('autoConnect', value);
  }

  /// Kill switch (not stop VPN on unexpected disconnect)
  bool get killSwitch => _prefs?.getBool('killSwitch') ?? false;
  Future<void> setKillSwitch(bool value) async {
    await init();
    await _prefs!.setBool('killSwitch', value);
  }

  // --- DNS Settings ---

  /// DNS provider preset: 'cloudflare', 'google', 'quad9', 'custom'
  String get dnsProvider => _prefs?.getString('dnsProvider') ?? 'cloudflare';
  Future<void> setDnsProvider(String value) async {
    await init();
    await _prefs!.setString('dnsProvider', value);
  }

  /// Custom DNS address (DoH URL or IP)
  String get customDns => _prefs?.getString('customDns') ?? '';
  Future<void> setCustomDns(String value) async {
    await init();
    await _prefs!.setString('customDns', value);
  }

  /// Get the actual DNS URL based on the current preset
  String get dnsUrl {
    switch (dnsProvider) {
      case 'cloudflare':
        return 'https://1.1.1.1/dns-query';
      case 'google':
        return 'https://dns.google/dns-query';
      case 'quad9':
        return 'https://dns.quad9.net/dns-query';
      case 'adguard':
        return 'https://dns.adguard-dns.com/dns-query';
      case 'alidns':
        return 'https://dns.alidns.com/dns-query';
      case 'custom':
        return customDns.isNotEmpty ? customDns : 'https://1.1.1.1/dns-query';
      default:
        return 'https://1.1.1.1/dns-query';
    }
  }

  // --- Subscription Settings ---

  /// Subscription refresh interval in hours
  int get subRefreshHours => _prefs?.getInt('subRefreshHours') ?? 12;
  Future<void> setSubRefreshHours(int value) async {
    await init();
    await _prefs!.setInt('subRefreshHours', value);
  }

  // --- App Info ---

  static const String appVersion = '1.0.0';
  static const String appName = 'Zen Privacy';
}
