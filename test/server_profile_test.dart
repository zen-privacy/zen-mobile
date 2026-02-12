import 'package:flutter_test/flutter_test.dart';
import 'package:zen_security/models/server_profile.dart';

void main() {
  group('ServerProfile.fromLink', () {
    test('returns null for empty string', () {
      expect(ServerProfile.fromLink(''), isNull);
    });

    test('returns null for unsupported scheme', () {
      expect(ServerProfile.fromLink('http://example.com'), isNull);
      expect(ServerProfile.fromLink('ss://something'), isNull);
      expect(ServerProfile.fromLink('trojan://something'), isNull);
    });

    test('returns null for garbage input', () {
      expect(ServerProfile.fromLink('not a link at all'), isNull);
    });

    test('trims whitespace before parsing', () {
      final link =
          '  vless://uuid-1234@1.2.3.4:443?security=tls&type=ws#Test  ';
      final profile = ServerProfile.fromLink(link);
      expect(profile, isNotNull);
      expect(profile!.address, '1.2.3.4');
    });
  });

  group('ServerProfile.fromVlessLink', () {
    test('parses basic VLESS WS+TLS link', () {
      const link =
          'vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?type=ws&security=tls&path=%2Fws&host=cdn.example.com#My+Server';
      final profile = ServerProfile.fromVlessLink(link);

      expect(profile, isNotNull);
      expect(profile!.protocol, 'VLESS');
      expect(profile.uuid, '550e8400-e29b-41d4-a716-446655440000');
      expect(profile.address, 'example.com');
      expect(profile.port, 443);
      expect(profile.security, 'tls');
      expect(profile.transportType, 'ws');
      expect(profile.path, '/ws');
      expect(profile.host, 'cdn.example.com');
      expect(profile.name, 'MY+SERVER');
      expect(profile.rawLink, link);
    });

    test('parses VLESS REALITY link', () {
      const link =
          'vless://uuid123@10.0.0.1:443?type=tcp&security=reality&pbk=publickey123&sid=ab12&flow=xtls-rprx-vision&fp=chrome&sni=www.google.com#Reality%20Node';
      final profile = ServerProfile.fromVlessLink(link);

      expect(profile, isNotNull);
      expect(profile!.security, 'reality');
      expect(profile.transportType, 'tcp');
      expect(profile.publicKey, 'publickey123');
      expect(profile.shortId, 'ab12');
      expect(profile.flow, 'xtls-rprx-vision');
      expect(profile.fingerprint, 'chrome');
      expect(profile.host, 'www.google.com');
      expect(profile.name, 'REALITY NODE');
    });

    test('defaults to port 443 for non-numeric port', () {
      const link = 'vless://uuid@server.com:abc?security=tls&type=ws#Test';
      final profile = ServerProfile.fromVlessLink(link);
      expect(profile, isNotNull);
      expect(profile!.port, 443);
    });

    test('defaults security=tls and type=ws when no query params', () {
      const link = 'vless://uuid@server.com:8443#Bare';
      final profile = ServerProfile.fromVlessLink(link);
      expect(profile, isNotNull);
      expect(profile!.security, 'tls');
      expect(profile.transportType, 'ws');
    });

    test('defaults name to VLESS SERVER when no fragment', () {
      const link = 'vless://uuid@server.com:443?type=ws&security=tls';
      final profile = ServerProfile.fromVlessLink(link);
      expect(profile, isNotNull);
      expect(profile!.name, 'VLESS SERVER');
    });

    test('returns null if no @ separator', () {
      const link = 'vless://uuidserver.com:443';
      expect(ServerProfile.fromVlessLink(link), isNull);
    });

    test('returns null if no : in host:port', () {
      const link = 'vless://uuid@servercom443';
      expect(ServerProfile.fromVlessLink(link), isNull);
    });

    test('returns null for non-vless scheme', () {
      expect(ServerProfile.fromVlessLink('http://uuid@server:443'), isNull);
    });

    test('decodes URL-encoded fragment name', () {
      const link =
          'vless://uuid@server.com:443?security=tls&type=ws#%D0%9C%D0%BE%D1%81%D0%BA%D0%B2%D0%B0';
      final profile = ServerProfile.fromVlessLink(link);
      expect(profile, isNotNull);
      expect(profile!.name, 'МОСКВА');
    });

    test('parses gRPC transport type', () {
      const link =
          'vless://uuid@server.com:443?type=grpc&security=tls#gRPC+Node';
      final profile = ServerProfile.fromVlessLink(link);
      expect(profile, isNotNull);
      expect(profile!.transportType, 'grpc');
    });
  });

  group('ServerProfile.fromHysteria2Link', () {
    test('parses basic hysteria2:// link', () {
      const link =
          'hysteria2://mypassword123@147.93.186.79:4443?sni=example.com#HY2+Server';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.protocol, 'HYSTERIA2');
      expect(profile.password, 'mypassword123');
      expect(profile.address, '147.93.186.79');
      expect(profile.port, 4443);
      expect(profile.sni, 'example.com');
      expect(profile.name, 'HY2+SERVER');
      expect(profile.rawLink, link);
    });

    test('parses hy2:// shorthand scheme', () {
      const link = 'hy2://pass@10.0.0.1:443?sni=test.com#Short';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.protocol, 'HYSTERIA2');
      expect(profile.password, 'pass');
      expect(profile.address, '10.0.0.1');
    });

    test('parses link with obfuscation params', () {
      const link =
          'hysteria2://pass@server.com:443?sni=sni.com&obfs=salamander&obfs-password=secret#Obfs';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.obfsType, 'salamander');
      expect(profile.obfsPassword, 'secret');
    });

    test('parses bandwidth limits', () {
      const link =
          'hysteria2://pass@server.com:443?upmbps=50&downmbps=200#BW';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.upMbps, 50);
      expect(profile.downMbps, 200);
    });

    test('parses insecure=1 flag', () {
      const link =
          'hysteria2://pass@server.com:443?insecure=1#Insecure';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.insecure, isTrue);
    });

    test('parses insecure=true flag', () {
      const link =
          'hysteria2://pass@server.com:443?insecure=true#Insecure';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.insecure, isTrue);
    });

    test('insecure defaults to false', () {
      const link = 'hysteria2://pass@server.com:443#Default';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.insecure, isFalse);
    });

    test('parses IPv6 address in brackets', () {
      const link =
          'hysteria2://pass@[::1]:443?sni=test.com#IPv6';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.address, '::1');
      expect(profile.port, 443);
    });

    test('defaults to port 443 for IPv6 without port', () {
      const link = 'hysteria2://pass@[::1]#IPv6NoPort';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.port, 443);
    });

    test('defaults name to HYSTERIA2 SERVER when no fragment', () {
      const link = 'hysteria2://pass@server.com:443';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.name, 'HYSTERIA2 SERVER');
    });

    test('returns null if no @ separator', () {
      const link = 'hysteria2://passserver.com:443';
      expect(ServerProfile.fromHysteria2Link(link), isNull);
    });

    test('returns null for wrong scheme', () {
      expect(ServerProfile.fromHysteria2Link('vless://pass@s:443'), isNull);
    });

    test('URL-decodes password', () {
      const link =
          'hysteria2://my%40pass%3Dword@server.com:443#Encoded';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.password, 'my@pass=word');
    });

    test('parses peer param as sni fallback', () {
      const link =
          'hysteria2://pass@server.com:443?peer=peer.example.com#Peer';
      final profile = ServerProfile.fromHysteria2Link(link);

      expect(profile, isNotNull);
      expect(profile!.sni, 'peer.example.com');
    });
  });

  group('ServerProfile.protocolLabel', () {
    test('returns HY2 for HYSTERIA2 protocol', () {
      final p = ServerProfile(
        name: 'Test',
        address: '1.2.3.4',
        port: 443,
        protocol: 'HYSTERIA2',
      );
      expect(p.protocolLabel, 'HY2');
    });

    test('returns VLESS/REALITY for reality security', () {
      final p = ServerProfile(
        name: 'Test',
        address: '1.2.3.4',
        port: 443,
        protocol: 'VLESS',
        security: 'reality',
      );
      expect(p.protocolLabel, 'VLESS/REALITY');
    });

    test('returns VLESS/WS for ws transport', () {
      final p = ServerProfile(
        name: 'Test',
        address: '1.2.3.4',
        port: 443,
        protocol: 'VLESS',
        security: 'tls',
        transportType: 'ws',
      );
      expect(p.protocolLabel, 'VLESS/WS');
    });

    test('returns VLESS/gRPC for grpc transport', () {
      final p = ServerProfile(
        name: 'Test',
        address: '1.2.3.4',
        port: 443,
        protocol: 'VLESS',
        security: 'tls',
        transportType: 'grpc',
      );
      expect(p.protocolLabel, 'VLESS/gRPC');
    });

    test('returns VLESS/TCP for tcp transport', () {
      final p = ServerProfile(
        name: 'Test',
        address: '1.2.3.4',
        port: 443,
        protocol: 'VLESS',
        security: 'tls',
        transportType: 'tcp',
      );
      expect(p.protocolLabel, 'VLESS/TCP');
    });
  });

  group('ServerProfile.toJson', () {
    test('serializes VLESS profile correctly', () {
      const link =
          'vless://uuid@server.com:443?type=ws&security=tls&path=%2Fws&host=cdn.com#Name';
      final profile = ServerProfile.fromVlessLink(link)!;
      final json = profile.toJson();

      expect(json['server'], 'server.com');
      expect(json['port'], 443);
      expect(json['protocol'], 'VLESS');
      expect(json['uuid'], 'uuid');
      expect(json['path'], '/ws');
      expect(json['host'], 'cdn.com');
      expect(json['security'], 'tls');
      expect(json['transportType'], 'ws');
    });

    test('serializes Hysteria2 profile correctly', () {
      const link =
          'hysteria2://pass@10.0.0.1:4443?sni=example.com&insecure=1#HY2';
      final profile = ServerProfile.fromHysteria2Link(link)!;
      final json = profile.toJson();

      expect(json['server'], '10.0.0.1');
      expect(json['port'], 4443);
      expect(json['protocol'], 'HYSTERIA2');
      expect(json['password'], 'pass');
      expect(json['sni'], 'example.com');
      expect(json['insecure'], isTrue);
      // host should fall back to sni
      expect(json['host'], 'example.com');
    });
  });
}
