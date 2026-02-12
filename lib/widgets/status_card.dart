import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/server_profile.dart';

class StatusCard extends StatelessWidget {
  final bool isConnected;
  final ServerProfile? server;
  final Duration uptime;

  const StatusCard({
    super.key,
    required this.isConnected,
    required this.server,
    required this.uptime,
  });

  String _formatUptime(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(
            'Status',
            isConnected ? 'Connected' : 'Disconnected',
            isConnected ? Colors.green : AppTheme.textMuted,
          ),
          const SizedBox(height: 8),
          _buildRow(
            'Server',
            server?.address ?? 'None',
            AppTheme.textLight,
          ),
          const SizedBox(height: 8),
          _buildRow(
            'Protocol',
            server?.protocolLabel ?? '-',
            AppTheme.textLight,
          ),
          const SizedBox(height: 8),
          _buildRow(
            'Uptime',
            isConnected ? _formatUptime(uptime) : '0h 0m 0s',
            AppTheme.accentGold,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'SpecialElite',
            fontSize: 12,
            color: AppTheme.textMuted,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'SpecialElite',
              fontSize: 12,
              color: valueColor,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
