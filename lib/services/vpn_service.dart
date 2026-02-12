import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/server_profile.dart';
import 'settings_service.dart';

/// VPN status events broadcast from native
enum VpnStatusType {
  disconnected,
  connecting,
  connected,
  disconnecting,
  reconnecting,
  error,
}

/// Parsed VPN status event
class VpnStatus {
  final VpnStatusType status;
  final String message;
  final String serverName;

  const VpnStatus({
    required this.status,
    this.message = '',
    this.serverName = '',
  });

  static VpnStatus fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String?)?.toLowerCase() ?? 'disconnected';
    VpnStatusType status;
    switch (statusStr) {
      case 'connecting':
        status = VpnStatusType.connecting;
        break;
      case 'connected':
        status = VpnStatusType.connected;
        break;
      case 'disconnecting':
        status = VpnStatusType.disconnecting;
        break;
      case 'reconnecting':
        status = VpnStatusType.reconnecting;
        break;
      case 'error':
        status = VpnStatusType.error;
        break;
      default:
        status = VpnStatusType.disconnected;
    }
    return VpnStatus(
      status: status,
      message: json['message'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
    );
  }
}

/// VPN Service - bridges to native Android/iOS VPN APIs
class VpnService {
  static const MethodChannel _channel = MethodChannel('com.zen.security/vpn');
  static const EventChannel _statusChannel = EventChannel('com.zen.security/vpn_status');
  
  static VpnService? _instance;
  static VpnService get instance => _instance ??= VpnService._();
  
  VpnService._() {
    _statusChannel.receiveBroadcastStream().listen(
      _onStatusEvent,
      onError: (e) => _statusController.addError(e),
    );
  }

  void _onStatusEvent(dynamic event) {
    if (event is String) {
      try {
        final json = jsonDecode(event) as Map<String, dynamic>;
        final status = VpnStatus.fromJson(json);
        _statusController.add(status);
        _isConnected = status.status == VpnStatusType.connected;
        _connectionStateController.add(_isConnected);
      } catch (e) {
        _statusController.addError(e);
      }
    }
  }

  /// VPN status stream (broadcast from native)
  final _statusController = StreamController<VpnStatus>.broadcast();
  Stream<VpnStatus> get statusStream => _statusController.stream;

  /// Connection state stream
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;

  /// Current VPN connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;


  /// Connect to VPN server.
  /// Returns true if the VPN service was started successfully (not necessarily connected yet).
  /// The actual connected/disconnected state is provided via [statusStream].
  /// A fallback poller ensures state is correct even if EventChannel doesn't deliver.
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

      final config = server.toJson();
      // Include DNS setting from preferences
      await SettingsService.instance.init();
      config['dnsUrl'] = SettingsService.instance.dnsUrl;

      final result = await _channel.invokeMethod('connect', {'config': config});
      final started = result == true;

      if (started) {
        // Service started. Broadcast "connecting" locally (in case EventChannel hasn't delivered yet).
        _statusController.add(const VpnStatus(status: VpnStatusType.connecting));

        // Start a fallback poller: if EventChannel doesn't deliver "connected" within a few seconds,
        // poll the native isConnected to update state.
        _startConnectFallbackPoller();
      }

      return started;
    } on PlatformException catch (e) {
      print('VPN connect error: ${e.message}');
      _isConnected = false;
      _connectionStateController.add(false);
      _statusController.add(VpnStatus(status: VpnStatusType.error, message: e.message ?? 'Connect failed'));
      return false;
    }
  }

  Timer? _connectFallbackTimer;

  /// Polls native isConnected every 2s for up to 15s as a fallback if EventChannel misses the event.
  void _startConnectFallbackPoller() {
    _connectFallbackTimer?.cancel();
    int attempts = 0;
    _connectFallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > 7) {
        timer.cancel();
        return;
      }
      // If we already received the connected status from EventChannel, stop polling.
      if (_isConnected) {
        timer.cancel();
        return;
      }
      try {
        final connected = await checkConnectionStatus();
        if (connected) {
          // EventChannel missed it — update manually.
          print('VPN: fallback poller detected connected state');
          _isConnected = true;
          _connectionStateController.add(true);
          _statusController.add(const VpnStatus(status: VpnStatusType.connected));
          timer.cancel();
        }
      } catch (_) {}
    });
  }

  /// Disconnect from VPN.
  /// The actual disconnected state is provided via [statusStream] / fallback.
  Future<bool> disconnect() async {
    try {
      _connectFallbackTimer?.cancel();
      _statusController.add(const VpnStatus(status: VpnStatusType.disconnecting));

      final result = await _channel.invokeMethod('disconnect');

      // Start a fallback poller for disconnect too
      _startDisconnectFallbackPoller();
      return result == true;
    } on PlatformException catch (e) {
      print('VPN disconnect error: ${e.message}');
      return false;
    }
  }

  Timer? _disconnectFallbackTimer;

  void _startDisconnectFallbackPoller() {
    _disconnectFallbackTimer?.cancel();
    int attempts = 0;
    _disconnectFallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > 5) {
        timer.cancel();
        // Force disconnected state after timeout
        if (_isConnected) {
          _isConnected = false;
          _connectionStateController.add(false);
          _statusController.add(const VpnStatus(status: VpnStatusType.disconnected));
        }
        return;
      }
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      try {
        final connected = await checkConnectionStatus();
        if (!connected) {
          print('VPN: fallback poller detected disconnected state');
          _isConnected = false;
          _connectionStateController.add(false);
          _statusController.add(const VpnStatus(status: VpnStatusType.disconnected));
          timer.cancel();
        }
      } catch (_) {}
    });
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

  void dispose() {
    _statusController.close();
    _connectionStateController.close();
  }
}
