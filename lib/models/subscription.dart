/// Represents a VPN subscription with URL, metadata, and usage info.
class Subscription {
  final String url;
  final String? name;
  final DateTime? lastUpdated;
  final int? refreshIntervalHours; // from Profile-Update-Interval header
  final SubscriptionUsage? usage;

  Subscription({
    required this.url,
    this.name,
    this.lastUpdated,
    this.refreshIntervalHours,
    this.usage,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'lastUpdated': lastUpdated?.toIso8601String(),
    'refreshIntervalHours': refreshIntervalHours,
  };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    url: json['url'] as String,
    name: json['name'] as String?,
    lastUpdated: json['lastUpdated'] != null
        ? DateTime.tryParse(json['lastUpdated'] as String)
        : null,
    refreshIntervalHours: json['refreshIntervalHours'] as int?,
  );
}

/// Usage info parsed from Subscription-Userinfo header.
/// Format: upload=bytes; download=bytes; total=bytes; expire=timestamp
class SubscriptionUsage {
  final int uploadBytes;
  final int downloadBytes;
  final int totalBytes;
  final DateTime? expiresAt;

  SubscriptionUsage({
    required this.uploadBytes,
    required this.downloadBytes,
    required this.totalBytes,
    this.expiresAt,
  });

  int get usedBytes => uploadBytes + downloadBytes;
  double get usedPercent => totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  int get remainingBytes => (totalBytes - usedBytes).clamp(0, totalBytes);

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Parse Subscription-Userinfo header value.
  /// Format: upload=0; download=1234567; total=10737418240; expire=1700000000
  static SubscriptionUsage? parse(String? headerValue) {
    if (headerValue == null || headerValue.isEmpty) return null;

    final parts = headerValue.split(';').map((p) => p.trim());
    int upload = 0;
    int download = 0;
    int total = 0;
    DateTime? expires;

    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toLowerCase();
      final value = kv[1].trim();

      switch (key) {
        case 'upload':
          upload = int.tryParse(value) ?? 0;
          break;
        case 'download':
          download = int.tryParse(value) ?? 0;
          break;
        case 'total':
          total = int.tryParse(value) ?? 0;
          break;
        case 'expire':
          final ts = int.tryParse(value);
          if (ts != null && ts > 0) {
            expires = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
          break;
      }
    }

    return SubscriptionUsage(
      uploadBytes: upload,
      downloadBytes: download,
      totalBytes: total,
      expiresAt: expires,
    );
  }
}
