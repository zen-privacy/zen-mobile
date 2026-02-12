import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';
import '../services/ping_service.dart';
import '../services/subscription_service.dart';
import '../services/vpn_service.dart' show VpnService, VpnStatusType;
import 'settings_screen.dart';
import '../widgets/mask_button.dart';
import '../widgets/server_card.dart';
import '../widgets/status_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VpnService _vpnService = VpnService.instance;
  
  bool isConnected = false;
  bool isConnecting = false;
  bool isDisconnecting = false;
  ServerProfile? selectedServer;
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _subController = TextEditingController();
  
  List<ServerProfile> servers = [];
  SubscriptionUsage? _subscriptionUsage;
  bool _isLoadingSub = false;
  Duration uptime = Duration.zero;
  Timer? _uptimeTimer;
  DateTime? _connectedAt;
  bool _showLogs = false;
  List<String> _logs = [];
  Timer? _logTimer;

  VpnStatusType _vpnStatus = VpnStatusType.disconnected;
  String _vpnError = '';

  @override
  void initState() {
    super.initState();
    _loadServers();
    _loadSubscriptions();
    _checkConnectionStatus();
    
    // Listen to real VPN status from native
    _vpnService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _vpnStatus = status.status;
          isConnected = status.status == VpnStatusType.connected;
          isConnecting = status.status == VpnStatusType.connecting;
          isDisconnecting = status.status == VpnStatusType.disconnecting;
          
          if (status.status == VpnStatusType.error) {
            _vpnError = status.message;
            isConnecting = false;
          }
          
          if (isConnected && _connectedAt == null) {
            _connectedAt = DateTime.now();
            _startUptimeTimer();
          } else if (!isConnected) {
            _stopUptimeTimer();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _logTimer?.cancel();
    _linkController.dispose();
    _subController.dispose();
    SubscriptionService.instance.stopAutoRefresh();
    super.dispose();
  }

  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
      if (_showLogs) {
        _refreshLogs();
        _logTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshLogs());
      } else {
        _logTimer?.cancel();
        _logTimer = null;
      }
    });
  }

  Future<void> _refreshLogs() async {
    final logs = await _vpnService.getLogs();
    if (mounted) {
      setState(() => _logs = logs);
    }
  }

  Future<void> _loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serverLinks = prefs.getStringList('servers') ?? [];
    
    setState(() {
      servers = serverLinks
          .map((link) => ServerProfile.fromLink(link))
          .whereType<ServerProfile>()
          .toList();
      
      // Select first server by default
      if (servers.isNotEmpty && selectedServer == null) {
        selectedServer = servers.first;
      }
    });

    // Ping all servers in the background
    if (servers.isNotEmpty) {
      _pingAllServers();
    }
  }

  Future<void> _pingAllServers() async {
    await PingService.instance.pingAll(servers);
    if (mounted) setState(() {});
  }

  Future<void> _loadSubscriptions() async {
    await SubscriptionService.instance.loadSubscriptions();
    // Start auto-refresh
    SubscriptionService.instance.startAutoRefresh(onRefresh: (newServers) {
      if (mounted && newServers.isNotEmpty) {
        setState(() {
          _mergeSubscriptionServers(newServers);
        });
      }
    });
  }

  Future<void> _addSubscription() async {
    final url = _subController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoadingSub = true);

    final result = await SubscriptionService.instance.addSubscription(url);
    
    if (!mounted) return;

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: AppTheme.redPrimary,
        ),
      );
      setState(() => _isLoadingSub = false);
      return;
    }

    _subController.clear();
    setState(() {
      _subscriptionUsage = result.usage;
      _mergeSubscriptionServers(result.servers);
      _isLoadingSub = false;
    });

    await _saveServers();
    _pingAllServers();

    if (result.servers.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${result.servers.length} servers from subscription'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _refreshSubscriptions() async {
    setState(() => _isLoadingSub = true);
    final newServers = await SubscriptionService.instance.refreshAll();
    if (!mounted) return;
    setState(() {
      _mergeSubscriptionServers(newServers);
      _isLoadingSub = false;
    });
    await _saveServers();
    _pingAllServers();
  }

  void _mergeSubscriptionServers(List<ServerProfile> newServers) {
    // Replace subscription servers (keep manually added ones)
    // For simplicity, add new servers that don't already exist (by rawLink)
    final existingLinks = servers.map((s) => s.rawLink).toSet();
    for (final server in newServers) {
      if (!existingLinks.contains(server.rawLink)) {
        servers.add(server);
        existingLinks.add(server.rawLink);
      }
    }
    if (selectedServer == null && servers.isNotEmpty) {
      selectedServer = servers.first;
    }
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final links = servers.map((s) => s.rawLink).where((l) => l.isNotEmpty).toList();
    await prefs.setStringList('servers', links);
  }

  // --- Status helpers ---
  Color get _statusDotColor {
    switch (_vpnStatus) {
      case VpnStatusType.connected:
        return Colors.green;
      case VpnStatusType.connecting:
      case VpnStatusType.reconnecting:
        return Colors.amber;
      case VpnStatusType.disconnecting:
        return Colors.orange;
      case VpnStatusType.error:
        return Colors.red;
      case VpnStatusType.disconnected:
        return Colors.grey;
    }
  }

  Color get _statusBorderColor {
    switch (_vpnStatus) {
      case VpnStatusType.connected:
        return Colors.greenAccent;
      case VpnStatusType.connecting:
      case VpnStatusType.reconnecting:
        return Colors.amberAccent;
      case VpnStatusType.error:
        return Colors.redAccent;
      default:
        return Colors.white24;
    }
  }

  String get _statusLabel {
    switch (_vpnStatus) {
      case VpnStatusType.connecting:
        return 'CONNECTING...';
      case VpnStatusType.connected:
        return 'CONNECTED';
      case VpnStatusType.disconnecting:
        return 'DISCONNECTING...';
      case VpnStatusType.reconnecting:
        return 'RECONNECTING...';
      case VpnStatusType.error:
        return 'ERROR';
      case VpnStatusType.disconnected:
        return 'CONNECT';
    }
  }

  String get _statusSubLabel {
    if (_vpnStatus == VpnStatusType.connecting || _vpnStatus == VpnStatusType.disconnecting) {
      return 'PLEASE WAIT';
    }
    if (_vpnStatus == VpnStatusType.reconnecting) {
      return 'CONNECTION LOST, RETRYING...';
    }
    if (_vpnStatus == VpnStatusType.error && _vpnError.isNotEmpty) {
      return _vpnError.toUpperCase();
    }
    return '';
  }

  Future<void> _checkConnectionStatus() async {
    final connected = await _vpnService.checkConnectionStatus();
    if (mounted) {
      setState(() {
        isConnected = connected;
        if (connected) {
          _connectedAt = DateTime.now();
          _startUptimeTimer();
        }
      });
    }
  }

  void _startUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null && mounted) {
        setState(() {
          uptime = DateTime.now().difference(_connectedAt!);
        });
      }
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    uptime = Duration.zero;
    _connectedAt = null;
  }

  void _handleConnect() async {
    if (isConnecting || isDisconnecting) return;
    
    if (isConnected) {
      // Disconnect — let EventChannel handle state transitions
      setState(() {
        isDisconnecting = true;
        _vpnStatus = VpnStatusType.disconnecting;
      });
      
      await _vpnService.disconnect();
      // Don't set state manually — EventChannel will broadcast disconnected
      return;
    } else {
      // Connect
      if (selectedServer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a server first'),
            backgroundColor: AppTheme.redPrimary,
          ),
        );
        return;
      }
      
      setState(() {
        isConnecting = true;
        _vpnStatus = VpnStatusType.connecting;
      });
      
      final success = await _vpnService.connect(selectedServer!);
      
      // If connect() returned false, it means permission was denied or error
      // EventChannel will handle the actual connected/error status
      if (!success && mounted) {
        setState(() {
          isConnecting = false;
          _vpnStatus = VpnStatusType.disconnected;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start VPN (permission denied?)'),
            backgroundColor: AppTheme.redPrimary,
          ),
        );
      }
      // Otherwise, EventChannel status stream handles state transitions
    }
  }

  void _addServer() {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;
    
    // Parse server link (VLESS or Hysteria2)
    final parsed = ServerProfile.fromLink(link);
    if (parsed != null) {
      setState(() {
        servers.add(parsed);
        _linkController.clear();
        if (selectedServer == null) {
          selectedServer = parsed;
        }
      });
      _saveServers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid link. Supported: vless://, hysteria2://, hy2://'),
          backgroundColor: AppTheme.redPrimary,
        ),
      );
    }
  }

  void _deleteServer(ServerProfile server) {
    // Don't delete while connected to this server
    if (isConnected && selectedServer == server) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnect before deleting'),
          backgroundColor: AppTheme.redPrimary,
        ),
      );
      return;
    }
    
    setState(() {
      servers.remove(server);
      if (selectedServer == server) {
        selectedServer = servers.isNotEmpty ? servers.first : null;
      }
    });
    _saveServers();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.bgDarker, AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(),
              
              // Main content
              Expanded(
                child: _showLogs ? _buildLogPanel() : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Connect Panel with Mask
                      _buildConnectPanel(),

                      const SizedBox(height: 24),

                      // Status Card
                      StatusCard(
                        isConnected: isConnected,
                        server: selectedServer,
                        uptime: uptime,
                      ),

                      const SizedBox(height: 24),

                      // Servers Section
                      _buildServersSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgDarker,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Icon(
              Icons.settings,
              color: AppTheme.textMuted,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'ZEN PRIVACY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'BebasNeue',
                fontSize: 24,
                letterSpacing: 4,
                color: AppTheme.textLight,
                shadows: [
                  Shadow(
                    color: AppTheme.redPrimary.withOpacity(0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _toggleLogs,
            child: Icon(
              _showLogs ? Icons.close : Icons.terminal,
              color: _showLogs ? AppTheme.redPrimary : AppTheme.textMuted,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.redPrimary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.redDark.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Mask Button
          MaskButton(
            isConnected: isConnected,
            isConnecting: isConnecting,
            isDisconnecting: isDisconnecting,
            onTap: _handleConnect,
          ),
          
          const SizedBox(height: 16),
          
          // Status indicator
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusDotColor,
              boxShadow: isConnected ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ] : _vpnStatus == VpnStatusType.error ? [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ] : null,
              border: Border.all(
                color: _statusBorderColor,
                width: 2,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Connect/Disconnect text
          Text(
            _statusLabel,
            style: const TextStyle(
              fontFamily: 'BebasNeue',
              fontSize: 20,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          
          // Sub-label (wait, error, reconnecting info)
          if (_statusSubLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _statusSubLabel,
                style: TextStyle(
                  fontFamily: 'SpecialElite',
                  fontSize: 12,
                  color: _vpnStatus == VpnStatusType.error 
                      ? AppTheme.redPrimary 
                      : AppTheme.accentGold,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  'LOGS (${_logs.length})',
                  style: const TextStyle(
                    fontFamily: 'BebasNeue',
                    fontSize: 16,
                    color: Colors.green,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (_logs.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.copy, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _refreshLogs,
                  child: const Icon(Icons.refresh, color: Colors.green, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.green),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No logs yet.\nTry connecting to a server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    reverse: true,
                    itemBuilder: (context, index) {
                      final log = _logs[_logs.length - 1 - index];
                      Color color = Colors.grey;
                      if (log.contains('ERROR') || log.contains('FAILED')) {
                        color = Colors.red;
                      } else if (log.contains('WARN')) {
                        color = Colors.orange;
                      } else if (log.contains('INFO')) {
                        color = Colors.green;
                      } else if (log.contains('BOX')) {
                        color = Colors.cyan;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: color,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionUsageBar() {
    if (_subscriptionUsage == null) return const SizedBox.shrink();
    final usage = _subscriptionUsage!;
    final usedPercent = usage.usedPercent;
    final usedStr = _formatBytes(usage.usedBytes);
    final totalStr = _formatBytes(usage.totalBytes);
    final expireStr = usage.expiresAt != null
        ? '${usage.expiresAt!.year}-${usage.expiresAt!.month.toString().padLeft(2, '0')}-${usage.expiresAt!.day.toString().padLeft(2, '0')}'
        : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DATA USAGE: $usedStr / $totalStr',
                style: const TextStyle(
                  fontFamily: 'SpecialElite',
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
              if (expireStr.isNotEmpty)
                Text(
                  'Expires: $expireStr',
                  style: TextStyle(
                    fontFamily: 'SpecialElite',
                    fontSize: 10,
                    color: usage.isExpired ? Colors.red : AppTheme.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usedPercent,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                usedPercent > 0.9 ? Colors.red : usedPercent > 0.7 ? Colors.orange : AppTheme.accentGold,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subscription URL input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subController,
                style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                decoration: const InputDecoration(
                  hintText: 'Subscription URL',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _addSubscription(),
              ),
            ),
            const SizedBox(width: 8),
            _isLoadingSub
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGold),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _addSubscription,
                    child: const Text(
                      'LOAD',
                      style: TextStyle(fontFamily: 'BebasNeue', fontSize: 14, letterSpacing: 1),
                    ),
                  ),
          ],
        ),

        if (SubscriptionService.instance.subscriptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSubscriptionUsageBar()),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppTheme.accentGold, size: 20),
                onPressed: _isLoadingSub ? null : _refreshSubscriptions,
                tooltip: 'Refresh subscriptions',
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SERVERS',
              style: TextStyle(
                fontFamily: 'BebasNeue',
                fontSize: 22,
                letterSpacing: 3,
                color: AppTheme.textLight,
              ),
            ),
            if (servers.isNotEmpty)
              Text(
                '${servers.length} server${servers.length == 1 ? "" : "s"}',
                style: const TextStyle(
                  fontFamily: 'SpecialElite',
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Server list
        if (servers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: const Center(
              child: Text(
                'No servers added yet.\nPaste a VLESS or Hysteria2 link below.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SpecialElite',
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          )
        else
          ...servers.map((server) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ServerCard(
              server: server,
              isSelected: selectedServer == server,
              onTap: isConnected ? null : () => setState(() => selectedServer = server),
              onDelete: () => _deleteServer(server),
              latencyMs: PingService.instance.getLatency(server),
            ),
          )),
        
        const SizedBox(height: 16),
        
        // Add server input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _linkController,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textLight,
                ),
                decoration: const InputDecoration(
                  hintText: 'Add New Server Link',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _addServer(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addServer,
              child: const Text(
                'ADD',
                style: TextStyle(
                  fontFamily: 'BebasNeue',
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
