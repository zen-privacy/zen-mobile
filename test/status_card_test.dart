import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_security/models/server_profile.dart';
import 'package:zen_security/widgets/status_card.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('StatusCard', () {
    testWidgets('shows Disconnected when not connected',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithMaterial(
        const StatusCard(
          isConnected: false,
          server: null,
          uptime: Duration.zero,
        ),
      ));

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('0h 0m 0s'), findsOneWidget);
    });

    testWidgets('shows Connected with server info when connected',
        (WidgetTester tester) async {
      final server = ServerProfile(
        name: 'Test Node',
        address: '10.0.0.1',
        port: 443,
        protocol: 'HYSTERIA2',
      );

      await tester.pumpWidget(wrapWithMaterial(
        StatusCard(
          isConnected: true,
          server: server,
          uptime: const Duration(hours: 1, minutes: 23, seconds: 45),
        ),
      ));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('10.0.0.1'), findsOneWidget);
      expect(find.text('HY2'), findsOneWidget);
      expect(find.text('1h 23m 45s'), findsOneWidget);
    });

    testWidgets('shows VLESS/REALITY protocol label',
        (WidgetTester tester) async {
      final server = ServerProfile(
        name: 'Reality',
        address: '192.168.1.1',
        port: 443,
        protocol: 'VLESS',
        security: 'reality',
      );

      await tester.pumpWidget(wrapWithMaterial(
        StatusCard(
          isConnected: true,
          server: server,
          uptime: Duration.zero,
        ),
      ));

      expect(find.text('VLESS/REALITY'), findsOneWidget);
    });

    testWidgets('shows 0h 0m 0s when disconnected regardless of uptime',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithMaterial(
        const StatusCard(
          isConnected: false,
          server: null,
          uptime: Duration(hours: 5),
        ),
      ));

      // When disconnected, uptime row should show zero
      expect(find.text('0h 0m 0s'), findsOneWidget);
    });

    testWidgets('renders all 4 info rows', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithMaterial(
        const StatusCard(
          isConnected: false,
          server: null,
          uptime: Duration.zero,
        ),
      ));

      expect(find.text('Status:'), findsOneWidget);
      expect(find.text('Server:'), findsOneWidget);
      expect(find.text('Protocol:'), findsOneWidget);
      expect(find.text('Uptime:'), findsOneWidget);
    });
  });
}
