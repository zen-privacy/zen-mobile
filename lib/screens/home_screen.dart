import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/server_profile.dart';
import '../services/vpn_service.dart';
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
  
  List<ServerProfile> servers = [];
  Duration uptime = Duration.zero;
  Timer? _uptimeTimer;
  DateTime? _connectedAt;
  bool _showLogs = false;
  List<String> _logs = [];
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    _loadServers();
    _checkConnectionStatus();
    
    // Listen to connection state changes
    _vpnService.connectionState.listen((connected) {
      if (mounted) {
        setState(() {
          isConnected = connected;
          if (connected) {
            _connectedAt = DateTime.now();
            _startUptimeTimer();
          } else {
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
    super.dispose();
  }

  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
      if (_showLogs) {
        _refreshLogs();
        _logTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshLogs());
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
          .map((link) => ServerProfile.fromVlessLink(link))
          .whereType<ServerProfile>()
          .toList();
      
      // Select first server by default
      if (servers.isNotEmpty && selectedServer == null) {
        selectedServer = servers.first;
      }
    });
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final links = servers.map((s) => s.rawLink).where((l) => l.isNotEmpty).toList();
    await prefs.setStringList('servers', links);
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
      // Disconnect
      setState(() => isDisconnecting = true);
      
      final success = await _vpnService.disconnect();
      
      if (mounted) {
        setState(() {
          isConnected = !success;
          isDisconnecting = false;
          if (success) {
            _stopUptimeTimer();
          }
        });
      }
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
      
      setState(() => isConnecting = true);
      
      final success = await _vpnService.connect(selectedServer!);
      
      if (mounted) {
        setState(() {
          isConnected = success;
          isConnecting = false;
          if (success) {
            _connectedAt = DateTime.now();
            _startUptimeTimer();
          }
        });
        
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect'),
              backgroundColor: AppTheme.redPrimary,
            ),
          );
        }
      }
    }
  }

  void _addServer() {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;
    
    // Parse VLESS link
    if (link.startsWith('vless://')) {
      final parsed = ServerProfile.fromVlessLink(link);
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
            content: Text('Invalid VLESS link'),
            backgroundColor: AppTheme.redPrimary,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only VLESS links are supported'),
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
                        rxBytes: _vpnService.rxBytes,
                        txBytes: _vpnService.txBytes,
                        formatBytes: _formatBytes,
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
          const SizedBox(width: 40),
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
              color: isConnected ? Colors.green : Colors.grey,
              boxShadow: isConnected ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ] : null,
              border: Border.all(
                color: isConnected ? Colors.greenAccent : Colors.white24,
                width: 2,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Connect/Disconnect text
          Text(
            isConnecting ? 'CONNECTING...' 
              : isDisconnecting ? 'DISCONNECTING...'
              : isConnected ? 'CONNECTED' : 'CONNECT',
            style: const TextStyle(
              fontFamily: 'BebasNeue',
              fontSize: 20,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          
          // Wait message
          if (isConnecting || isDisconnecting)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'PLEASE WAIT',
                style: TextStyle(
                  fontFamily: 'SpecialElite',
                  fontSize: 12,
                  color: AppTheme.accentGold,
                  letterSpacing: 1,
                ),
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

  Widget _buildServersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                'No servers added yet.\nPaste a VLESS link below.',
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
