import 'package:flutter_test/flutter_test.dart';
import 'package:zen_security/services/vpn_service.dart';

void main() {
  group('VpnStatus.fromJson', () {
    test('parses connected status', () {
      final status = VpnStatus.fromJson({
        'status': 'connected',
        'message': '',
        'serverName': 'My Server',
      });
      expect(status.status, VpnStatusType.connected);
      expect(status.serverName, 'My Server');
      expect(status.message, '');
    });

    test('parses connecting status', () {
      final status = VpnStatus.fromJson({'status': 'connecting'});
      expect(status.status, VpnStatusType.connecting);
    });

    test('parses disconnecting status', () {
      final status = VpnStatus.fromJson({'status': 'disconnecting'});
      expect(status.status, VpnStatusType.disconnecting);
    });

    test('parses disconnected status', () {
      final status = VpnStatus.fromJson({'status': 'disconnected'});
      expect(status.status, VpnStatusType.disconnected);
    });

    test('parses reconnecting status', () {
      final status = VpnStatus.fromJson({
        'status': 'reconnecting',
        'message': 'Attempt 2/5',
      });
      expect(status.status, VpnStatusType.reconnecting);
      expect(status.message, 'Attempt 2/5');
    });

    test('parses error status with message', () {
      final status = VpnStatus.fromJson({
        'status': 'error',
        'message': 'Connection timed out',
        'serverName': 'Node 1',
      });
      expect(status.status, VpnStatusType.error);
      expect(status.message, 'Connection timed out');
      expect(status.serverName, 'Node 1');
    });

    test('handles case-insensitive status strings', () {
      final status = VpnStatus.fromJson({'status': 'CONNECTED'});
      expect(status.status, VpnStatusType.connected);
    });

    test('defaults to disconnected for unknown status', () {
      final status = VpnStatus.fromJson({'status': 'unknown_state'});
      expect(status.status, VpnStatusType.disconnected);
    });

    test('defaults to disconnected when status is null', () {
      final status = VpnStatus.fromJson({});
      expect(status.status, VpnStatusType.disconnected);
    });

    test('defaults message and serverName to empty string when absent', () {
      final status = VpnStatus.fromJson({'status': 'connected'});
      expect(status.message, '');
      expect(status.serverName, '');
    });
  });

  group('VpnStatus const constructor', () {
    test('creates with required status', () {
      const status = VpnStatus(status: VpnStatusType.connected);
      expect(status.status, VpnStatusType.connected);
      expect(status.message, '');
      expect(status.serverName, '');
    });

    test('creates with all fields', () {
      const status = VpnStatus(
        status: VpnStatusType.error,
        message: 'timeout',
        serverName: 'Server A',
      );
      expect(status.message, 'timeout');
      expect(status.serverName, 'Server A');
    });
  });
}
