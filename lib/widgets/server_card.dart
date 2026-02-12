import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/server_profile.dart';

class ServerCard extends StatelessWidget {
  final ServerProfile server;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final int? latencyMs; // null = not measured, -1 = failed

  const ServerCard({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    this.latencyMs,
  });

  Color _latencyColor(int ms) {
    if (ms == -2) return Colors.cyanAccent; // UDP protocol
    if (ms < 0) return Colors.red;
    if (ms < 100) return Colors.greenAccent;
    if (ms < 300) return Colors.amber;
    return Colors.redAccent;
  }

  String _latencyText(int? ms) {
    if (ms == null) return '';
    if (ms == -2) return 'UDP';
    if (ms < 0) return 'timeout';
    return '${ms}ms';
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [AppTheme.redPrimary, AppTheme.redDark]
                : [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? AppTheme.accentGold 
                : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: isDisabled && !isSelected ? 0.5 : 1.0,
          child: Row(
            children: [
              // Server info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontFamily: 'BebasNeue',
                        fontSize: 18,
                        letterSpacing: 1,
                        color: isSelected ? Colors.white : AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${server.address}:${server.port} // ${server.protocolLabel}',
                      style: TextStyle(
                        fontFamily: 'SpecialElite',
                        fontSize: 11,
                        color: isSelected 
                            ? Colors.white.withOpacity(0.8)
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Latency badge
              if (latencyMs != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _latencyColor(latencyMs!).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _latencyColor(latencyMs!).withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    _latencyText(latencyMs),
                    style: TextStyle(
                      fontFamily: 'SpecialElite',
                      fontSize: 10,
                      color: _latencyColor(latencyMs!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              
              // Delete button
              if (!isSelected || !isDisabled)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: isSelected 
                        ? Colors.white.withOpacity(0.7)
                        : AppTheme.textMuted,
                  ),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
