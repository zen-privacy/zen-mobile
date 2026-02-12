import 'dart:async';
import 'dart:io';
import '../models/server_profile.dart';

/// Measures TCP connect latency to servers.
class PingService {
  static final PingService instance = PingService._();
  PingService._();

  /// Cached ping results: server address:port -> latency in ms (-1 = timeout/error)
  final Map<String, int> _cache = {};

  /// Get cached latency for a server, or null if not measured yet.
  int? getLatency(ServerProfile server) {
    return _cache['${server.address}:${server.port}'];
  }

  /// Ping a single server using TCP connect latency.
  /// For UDP-based protocols (Hysteria2), TCP ping doesn't apply — returns -2 (UDP).
  /// Returns latency in milliseconds, -1 on timeout/error, -2 for UDP protocols.
  Future<int> ping(ServerProfile server, {Duration timeout = const Duration(seconds: 5)}) async {
    final key = '${server.address}:${server.port}';

    // Hysteria2 uses UDP (QUIC) — TCP connect won't work
    if (server.protocol == 'HYSTERIA2') {
      _cache[key] = -2;
      return -2;
    }

    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        server.address,
        server.port,
        timeout: timeout,
      );
      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;
      await socket.close();
      socket.destroy();
      _cache[key] = latency;
      return latency;
    } catch (e) {
      _cache[key] = -1;
      return -1;
    }
  }

  /// Ping all servers concurrently. Returns map of address:port -> latency.
  Future<Map<String, int>> pingAll(List<ServerProfile> servers, {Duration timeout = const Duration(seconds: 5)}) async {
    final futures = servers.map((s) => ping(s, timeout: timeout));
    await Future.wait(futures);
    return Map.from(_cache);
  }

  /// Clear cached results.
  void clearCache() {
    _cache.clear();
  }
}
