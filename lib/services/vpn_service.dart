import 'dart:async';
import 'package:flutter/services.dart';
import '../models/server_profile.dart';

/// VPN Service - bridges to native Android/iOS VPN APIs
class VpnService {
  static const MethodChannel _channel = MethodChannel('com.zen.security/vpn');
  
  static VpnService? _instance;
  static VpnService get instance => _instance ??= VpnService._();
  
  VpnService._();

  /// Connection state stream
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;

  /// Current VPN connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// Traffic stats
  int _rxBytes = 0;
  int _txBytes = 0;
  int get rxBytes => _rxBytes;
  int get txBytes => _txBytes;

  Timer? _statsTimer;

  /// Connect to VPN server
  Future<bool> connect(ServerProfile server) async {
    try {
      // First check/request permission
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        final granted = await requestPermission();
        if (!granted) {
          return false;
        }
      }

      final config = {
        'server': server.address,
        'port': server.port,
        'uuid': server.uuid,
        'host': server.host ?? server.address,
        'path': server.path ?? '/',
        'protocol': server.protocol,
      };

      final result = await _channel.invokeMethod('connect', {'config': config});
      _isConnected = result == true;
      
      if (_isConnected) {
        _startStatsPolling();
      }
      
      _connectionStateController.add(_isConnected);
      return _isConnected;
    } on PlatformException catch (e) {
      print('VPN connect error: ${e.message}');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    try {
      final result = await _channel.invokeMethod('disconnect');
      _isConnected = !(result == true);
      _stopStatsPolling();
      _connectionStateController.add(_isConnected);
      return result == true;
    } on PlatformException catch (e) {
      print('VPN disconnect error: ${e.message}');
      return false;
    }
  }

  /// Check if VPN permission is granted
  Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod('checkPermission');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  /// Request VPN permission
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod('requestPermission');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  /// Check current connection status
  Future<bool> checkConnectionStatus() async {
    try {
      final result = await _channel.invokeMethod('isConnected');
      _isConnected = result == true;
      return _isConnected;
    } on PlatformException {
      return false;
    }
  }

  /// Get current traffic stats
  Future<Map<String, int>> getTrafficStats() async {
    try {
      final result = await _channel.invokeMethod('getTrafficStats');
      if (result != null) {
        _rxBytes = (result['rx'] as num?)?.toInt() ?? 0;
        _txBytes = (result['tx'] as num?)?.toInt() ?? 0;
      }
      return {'rx': _rxBytes, 'tx': _txBytes};
    } on PlatformException {
      return {'rx': 0, 'tx': 0};
    }
  }

  /// Get logs from native VPN service
  Future<List<String>> getLogs() async {
    try {
      final result = await _channel.invokeMethod('getLogs');
      if (result != null) {
        return (result as List).map((e) => e.toString()).toList();
      }
      return [];
    } on PlatformException {
      return [];
    }
  }

  /// Get last error
  Future<String?> getLastError() async {
    try {
      return await _channel.invokeMethod('getLastError');
    } on PlatformException {
      return null;
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      getTrafficStats();
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _rxBytes = 0;
    _txBytes = 0;
  }

  void dispose() {
    _statsTimer?.cancel();
    _connectionStateController.close();
  }
}
