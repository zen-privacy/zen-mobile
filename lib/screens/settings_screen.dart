import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;
  final _customDnsController = TextEditingController();

  bool _autoConnect = false;
  bool _killSwitch = false;
  String _dnsProvider = 'cloudflare';
  int _subRefreshHours = 12;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settings.init();
    setState(() {
      _autoConnect = _settings.autoConnect;
      _killSwitch = _settings.killSwitch;
      _dnsProvider = _settings.dnsProvider;
      _subRefreshHours = _settings.subRefreshHours;
      _customDnsController.text = _settings.customDns;
    });
  }

  @override
  void dispose() {
    _customDnsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('SETTINGS'),
        backgroundColor: AppTheme.bgDarker,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textLight),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Connection Section ---
          _buildSectionHeader('CONNECTION'),
          const SizedBox(height: 8),
          _buildToggleTile(
            title: 'Auto-connect',
            subtitle: 'Connect automatically when app starts',
            value: _autoConnect,
            onChanged: (v) async {
              setState(() => _autoConnect = v);
              await _settings.setAutoConnect(v);
            },
          ),
          _buildToggleTile(
            title: 'Kill Switch',
            subtitle: 'Block internet if VPN disconnects unexpectedly',
            value: _killSwitch,
            onChanged: (v) async {
              setState(() => _killSwitch = v);
              await _settings.setKillSwitch(v);
            },
          ),

          const SizedBox(height: 24),

          // --- DNS Section ---
          _buildSectionHeader('DNS'),
          const SizedBox(height: 8),
          _buildDnsTile('Cloudflare', 'cloudflare', '1.1.1.1 (DoH)'),
          _buildDnsTile('Google', 'google', '8.8.8.8 (DoH)'),
          _buildDnsTile('Quad9', 'quad9', '9.9.9.9 (DoH)'),
          _buildDnsTile('AdGuard', 'adguard', 'Block ads & trackers (DoH)'),
          _buildDnsTile('AliDNS', 'alidns', '223.5.5.5 (Alibaba DoH)'),
          _buildDnsTile('Custom', 'custom', 'Enter your own DNS'),
          if (_dnsProvider == 'custom') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customDnsController,
              style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
              decoration: const InputDecoration(
                hintText: 'https://dns.example.com/dns-query',
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => _settings.setCustomDns(v),
            ),
          ],

          const SizedBox(height: 24),

          // --- Subscription Section ---
          _buildSectionHeader('SUBSCRIPTION'),
          const SizedBox(height: 8),
          _buildDropdownTile(
            title: 'Refresh Interval',
            value: _subRefreshHours,
            items: const {1: '1 hour', 6: '6 hours', 12: '12 hours', 24: '24 hours', 48: '48 hours'},
            onChanged: (v) async {
              setState(() => _subRefreshHours = v);
              await _settings.setSubRefreshHours(v);
            },
          ),

          const SizedBox(height: 24),

          // --- About Section ---
          _buildSectionHeader('ABOUT'),
          const SizedBox(height: 8),
          _buildInfoTile('App', SettingsService.appName),
          _buildInfoTile('Version', SettingsService.appVersion),
          _buildInfoTile('Engine', 'sing-box (libbox)'),
          _buildInfoTile('Protocols', 'VLESS (WS, REALITY), Hysteria2'),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'BebasNeue',
        fontSize: 20,
        letterSpacing: 3,
        color: AppTheme.accentGold,
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'SpecialElite',
            fontSize: 14,
            color: AppTheme.textLight,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'SpecialElite',
            fontSize: 11,
            color: AppTheme.textMuted,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accentGold,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildDnsTile(String title, String value, String subtitle) {
    final isSelected = _dnsProvider == value;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.redPrimary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: AppTheme.accentGold.withOpacity(0.5)) : null,
      ),
      child: RadioListTile<String>(
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'SpecialElite',
            fontSize: 14,
            color: isSelected ? AppTheme.textLight : AppTheme.textMuted,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'SpecialElite',
            fontSize: 11,
            color: AppTheme.textMuted,
          ),
        ),
        value: value,
        groupValue: _dnsProvider,
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _dnsProvider = v);
          await _settings.setDnsProvider(v);
        },
        activeColor: AppTheme.accentGold,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        dense: true,
      ),
    );
  }

  Widget _buildDropdownTile({
    required String title,
    required int value,
    required Map<int, String> items,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'SpecialElite',
              fontSize: 14,
              color: AppTheme.textLight,
            ),
          ),
          DropdownButton<int>(
            value: value,
            dropdownColor: AppTheme.bgDarker,
            style: const TextStyle(
              fontFamily: 'SpecialElite',
              fontSize: 13,
              color: AppTheme.accentGold,
            ),
            underline: const SizedBox.shrink(),
            items: items.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'SpecialElite',
              fontSize: 13,
              color: AppTheme.textMuted,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'SpecialElite',
              fontSize: 13,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
