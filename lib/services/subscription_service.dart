import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';

/// Manages VPN subscriptions: fetching, parsing, auto-refresh.
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const String _subsKey = 'subscriptions';
  static const Duration defaultRefreshInterval = Duration(hours: 12);

  final List<Subscription> _subscriptions = [];
  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);

  Timer? _autoRefreshTimer;

  /// Load saved subscriptions from SharedPreferences.
  Future<void> loadSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_subsKey) ?? [];
    _subscriptions.clear();
    for (final jsonStr in jsonList) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _subscriptions.add(Subscription.fromJson(map));
      } catch (_) {}
    }
  }

  /// Save subscriptions to SharedPreferences.
  Future<void> _saveSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _subscriptions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_subsKey, jsonList);
  }

  /// Add a new subscription URL. Returns the fetched servers.
  Future<SubscriptionResult> addSubscription(String url) async {
    // Remove trailing whitespace
    url = url.trim();
    if (url.isEmpty) {
      return SubscriptionResult(servers: [], error: 'URL is empty');
    }

    // Check for duplicate
    if (_subscriptions.any((s) => s.url == url)) {
      return SubscriptionResult(servers: [], error: 'Subscription already exists');
    }

    // Fetch and parse
    final result = await fetchSubscription(url);
    if (result.error == null) {
      _subscriptions.add(Subscription(
        url: url,
        name: result.name,
        lastUpdated: DateTime.now(),
        refreshIntervalHours: result.refreshIntervalHours,
        usage: result.usage,
      ));
      await _saveSubscriptions();
    }
    return result;
  }

  /// Remove a subscription by URL.
  Future<void> removeSubscription(String url) async {
    _subscriptions.removeWhere((s) => s.url == url);
    await _saveSubscriptions();
  }

  /// Fetch subscription from URL, parse base64, return server profiles.
  Future<SubscriptionResult> fetchSubscription(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ZenPrivacy/1.0');
      final response = await request.close();

      if (response.statusCode != 200) {
        return SubscriptionResult(
          servers: [],
          error: 'HTTP ${response.statusCode}',
        );
      }

      // Read body
      final body = await response.transform(utf8.decoder).join();
      
      // Parse headers
      final userInfo = response.headers.value('subscription-userinfo');
      final usage = SubscriptionUsage.parse(userInfo);
      
      final updateInterval = response.headers.value('profile-update-interval');
      final refreshHours = updateInterval != null ? int.tryParse(updateInterval) : null;

      final profileTitle = response.headers.value('profile-title') ?? 
                           response.headers.value('content-disposition');
      String? name;
      if (profileTitle != null && profileTitle.isNotEmpty) {
        // Try to extract name from content-disposition or profile-title
        final cleaned = profileTitle
            .replaceAll(RegExp(r'(attachment|inline);\s*filename[*]?='), '')
            .replaceAll(RegExp(r'''['"]'''), '')
            .trim();
        if (cleaned.isNotEmpty) name = cleaned;
      }

      // Parse body: try base64 decode first, then plain text
      final servers = _parseSubscriptionBody(body);

      client.close();

      return SubscriptionResult(
        servers: servers,
        usage: usage,
        refreshIntervalHours: refreshHours,
        name: name,
      );
    } on SocketException catch (e) {
      return SubscriptionResult(servers: [], error: 'Network error: ${e.message}');
    } on HttpException catch (e) {
      return SubscriptionResult(servers: [], error: 'HTTP error: ${e.message}');
    } on FormatException catch (e) {
      return SubscriptionResult(servers: [], error: 'Parse error: ${e.message}');
    } catch (e) {
      return SubscriptionResult(servers: [], error: 'Error: $e');
    }
  }

  /// Parse subscription body. Tries base64 first, then plain text line-by-line.
  List<ServerProfile> _parseSubscriptionBody(String body) {
    final trimmed = body.trim();
    
    // Try base64 decode
    String decoded;
    try {
      decoded = utf8.decode(base64Decode(_normalizeBase64(trimmed)));
    } catch (_) {
      // Not base64, treat as plain text
      decoded = trimmed;
    }

    // Parse each line as a server link
    final lines = decoded.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    final servers = <ServerProfile>[];
    for (final line in lines) {
      final server = ServerProfile.fromLink(line);
      if (server != null) {
        servers.add(server);
      }
    }
    return servers;
  }

  /// Normalize base64 string (add padding if needed).
  String _normalizeBase64(String input) {
    // Remove whitespace
    var s = input.replaceAll(RegExp(r'\s'), '');
    // URL-safe to standard
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    // Add padding
    while (s.length % 4 != 0) {
      s += '=';
    }
    return s;
  }

  /// Refresh all subscriptions. Returns all servers from all subscriptions.
  Future<List<ServerProfile>> refreshAll() async {
    final allServers = <ServerProfile>[];
    for (var i = 0; i < _subscriptions.length; i++) {
      final result = await fetchSubscription(_subscriptions[i].url);
      if (result.error == null) {
        allServers.addAll(result.servers);
        _subscriptions[i] = Subscription(
          url: _subscriptions[i].url,
          name: result.name ?? _subscriptions[i].name,
          lastUpdated: DateTime.now(),
          refreshIntervalHours: result.refreshIntervalHours ?? _subscriptions[i].refreshIntervalHours,
          usage: result.usage,
        );
      }
    }
    await _saveSubscriptions();
    return allServers;
  }

  /// Start auto-refresh timer.
  void startAutoRefresh({Duration? interval, void Function(List<ServerProfile>)? onRefresh}) {
    _autoRefreshTimer?.cancel();
    final refreshInterval = interval ?? defaultRefreshInterval;
    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) async {
      final servers = await refreshAll();
      onRefresh?.call(servers);
    });
  }

  /// Stop auto-refresh timer.
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void dispose() {
    stopAutoRefresh();
  }
}

/// Result of fetching a subscription.
class SubscriptionResult {
  final List<ServerProfile> servers;
  final SubscriptionUsage? usage;
  final int? refreshIntervalHours;
  final String? name;
  final String? error;

  SubscriptionResult({
    required this.servers,
    this.usage,
    this.refreshIntervalHours,
    this.name,
    this.error,
  });
}
