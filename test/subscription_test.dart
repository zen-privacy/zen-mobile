import 'package:flutter_test/flutter_test.dart';
import 'package:zen_security/models/subscription.dart';

void main() {
  group('SubscriptionUsage.parse', () {
    test('parses complete header with all fields', () {
      const header =
          'upload=1073741824; download=5368709120; total=10737418240; expire=1700000000';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.uploadBytes, 1073741824); // 1 GB
      expect(usage.downloadBytes, 5368709120); // 5 GB
      expect(usage.totalBytes, 10737418240); // 10 GB
      expect(usage.expiresAt, isNotNull);
      expect(
        usage.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('parses header with zero upload', () {
      const header = 'upload=0; download=1234567; total=10000000';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.uploadBytes, 0);
      expect(usage.downloadBytes, 1234567);
      expect(usage.totalBytes, 10000000);
      expect(usage.expiresAt, isNull);
    });

    test('returns null for null input', () {
      expect(SubscriptionUsage.parse(null), isNull);
    });

    test('returns null for empty string', () {
      expect(SubscriptionUsage.parse(''), isNull);
    });

    test('handles missing fields gracefully (defaults to 0)', () {
      const header = 'total=5000000';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.uploadBytes, 0);
      expect(usage.downloadBytes, 0);
      expect(usage.totalBytes, 5000000);
    });

    test('handles malformed key=value pairs', () {
      const header = 'garbage;upload=100;also=bad=value;download=200;total=500';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.uploadBytes, 100);
      expect(usage.downloadBytes, 200);
      expect(usage.totalBytes, 500);
    });

    test('ignores expire=0', () {
      const header = 'upload=0; download=0; total=100; expire=0';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.expiresAt, isNull);
    });

    test('is case-insensitive for keys', () {
      const header = 'Upload=100; Download=200; Total=500; Expire=1700000000';
      final usage = SubscriptionUsage.parse(header);

      expect(usage, isNotNull);
      expect(usage!.uploadBytes, 100);
      expect(usage.downloadBytes, 200);
      expect(usage.totalBytes, 500);
      expect(usage.expiresAt, isNotNull);
    });
  });

  group('SubscriptionUsage computed fields', () {
    test('usedBytes = upload + download', () {
      final usage = SubscriptionUsage(
        uploadBytes: 1000,
        downloadBytes: 2000,
        totalBytes: 10000,
      );
      expect(usage.usedBytes, 3000);
    });

    test('usedPercent is correct fraction', () {
      final usage = SubscriptionUsage(
        uploadBytes: 250,
        downloadBytes: 250,
        totalBytes: 1000,
      );
      expect(usage.usedPercent, closeTo(0.5, 0.001));
    });

    test('usedPercent is clamped to 1.0 when over limit', () {
      final usage = SubscriptionUsage(
        uploadBytes: 600,
        downloadBytes: 600,
        totalBytes: 1000,
      );
      expect(usage.usedPercent, 1.0);
    });

    test('usedPercent is 0 when totalBytes is 0', () {
      final usage = SubscriptionUsage(
        uploadBytes: 100,
        downloadBytes: 200,
        totalBytes: 0,
      );
      expect(usage.usedPercent, 0.0);
    });

    test('remainingBytes is total minus used', () {
      final usage = SubscriptionUsage(
        uploadBytes: 1000,
        downloadBytes: 2000,
        totalBytes: 10000,
      );
      expect(usage.remainingBytes, 7000);
    });

    test('remainingBytes is clamped to 0 when over limit', () {
      final usage = SubscriptionUsage(
        uploadBytes: 6000,
        downloadBytes: 6000,
        totalBytes: 10000,
      );
      expect(usage.remainingBytes, 0);
    });

    test('isExpired returns true for past date', () {
      final usage = SubscriptionUsage(
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 1000,
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(usage.isExpired, isTrue);
    });

    test('isExpired returns false for future date', () {
      final usage = SubscriptionUsage(
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 1000,
        expiresAt: DateTime(2099, 12, 31),
      );
      expect(usage.isExpired, isFalse);
    });

    test('isExpired returns false when no expiry set', () {
      final usage = SubscriptionUsage(
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 1000,
      );
      expect(usage.isExpired, isFalse);
    });
  });

  group('Subscription serialization', () {
    test('toJson and fromJson roundtrip', () {
      final sub = Subscription(
        url: 'https://example.com/sub',
        name: 'My Sub',
        lastUpdated: DateTime.utc(2026, 2, 12, 10, 0, 0),
        refreshIntervalHours: 24,
      );

      final json = sub.toJson();
      expect(json['url'], 'https://example.com/sub');
      expect(json['name'], 'My Sub');
      expect(json['refreshIntervalHours'], 24);
      expect(json['lastUpdated'], isNotNull);

      final restored = Subscription.fromJson(json);
      expect(restored.url, sub.url);
      expect(restored.name, sub.name);
      expect(restored.refreshIntervalHours, sub.refreshIntervalHours);
      expect(restored.lastUpdated, sub.lastUpdated);
    });

    test('fromJson handles null optional fields', () {
      final sub = Subscription.fromJson({'url': 'https://example.com'});
      expect(sub.url, 'https://example.com');
      expect(sub.name, isNull);
      expect(sub.lastUpdated, isNull);
      expect(sub.refreshIntervalHours, isNull);
    });

    test('fromJson handles invalid lastUpdated gracefully', () {
      final sub = Subscription.fromJson({
        'url': 'https://example.com',
        'lastUpdated': 'not-a-date',
      });
      expect(sub.lastUpdated, isNull);
    });
  });
}
