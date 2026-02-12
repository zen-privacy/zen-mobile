class ServerProfile {
  final String name;
  final String address;
  final int port;
  final String protocol; // 'VLESS' or 'HYSTERIA2'

  // VLESS fields
  final String? uuid;
  final String? path;
  final String? host;

  // VLESS TLS/REALITY fields
  final String security;       // 'tls' or 'reality'
  final String transportType;  // 'ws', 'tcp', 'grpc', 'h2'
  final String? publicKey;     // REALITY pbk
  final String? shortId;       // REALITY sid
  final String? flow;          // e.g. 'xtls-rprx-vision'
  final String? fingerprint;   // uTLS fingerprint e.g. 'chrome'

  // Hysteria2 fields
  final String? password;
  final String? obfsPassword;
  final String? obfsType;
  final String? sni;
  final int? upMbps;
  final int? downMbps;
  final bool insecure;

  final String rawLink;

  ServerProfile({
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    this.uuid,
    this.path,
    this.host,
    this.security = 'tls',
    this.transportType = 'ws',
    this.publicKey,
    this.shortId,
    this.flow,
    this.fingerprint,
    this.password,
    this.obfsPassword,
    this.obfsType,
    this.sni,
    this.upMbps,
    this.downMbps,
    this.insecure = false,
    this.rawLink = '',
  });

  /// Human-readable protocol label for UI
  String get protocolLabel {
    if (protocol == 'HYSTERIA2') return 'HY2';
    if (security == 'reality') return 'VLESS/REALITY';
    if (transportType == 'ws') return 'VLESS/WS';
    if (transportType == 'grpc') return 'VLESS/gRPC';
    if (transportType == 'tcp') return 'VLESS/TCP';
    return 'VLESS';
  }

  /// Parse a server link (VLESS or Hysteria2)
  static ServerProfile? fromLink(String link) {
    final trimmed = link.trim();
    if (trimmed.startsWith('vless://')) {
      return fromVlessLink(trimmed);
    } else if (trimmed.startsWith('hysteria2://') || trimmed.startsWith('hy2://')) {
      return fromHysteria2Link(trimmed);
    }
    return null;
  }

  /// Parse VLESS link: vless://uuid@server:port?params#name
  /// Supports both WS+TLS and REALITY configurations
  static ServerProfile? fromVlessLink(String link) {
    try {
      if (!link.startsWith('vless://')) return null;

      final withoutScheme = link.substring(8);
      final hashIndex = withoutScheme.indexOf('#');
      final name = hashIndex != -1
          ? Uri.decodeComponent(withoutScheme.substring(hashIndex + 1))
          : 'VLESS Server';

      final mainPart = hashIndex != -1
          ? withoutScheme.substring(0, hashIndex)
          : withoutScheme;

      final atIndex = mainPart.indexOf('@');
      if (atIndex == -1) return null;

      final uuid = mainPart.substring(0, atIndex);
      final rest = mainPart.substring(atIndex + 1);

      final queryIndex = rest.indexOf('?');
      final hostPort = queryIndex != -1
          ? rest.substring(0, queryIndex)
          : rest;

      final colonIndex = hostPort.lastIndexOf(':');
      if (colonIndex == -1) return null;

      final address = hostPort.substring(0, colonIndex);
      final port = int.tryParse(hostPort.substring(colonIndex + 1)) ?? 443;

      // Parse query params
      String? path;
      String? host;
      String security = 'tls';
      String transportType = 'ws';
      String? publicKey;
      String? shortId;
      String? flow;
      String? fingerprint;

      if (queryIndex != -1) {
        final params = Uri.splitQueryString(rest.substring(queryIndex + 1));
        path = params['path'];
        host = params['host'] ?? params['sni'];
        security = params['security'] ?? 'tls';
        transportType = params['type'] ?? 'ws';
        publicKey = params['pbk'];
        shortId = params['sid'];
        flow = params['flow'];
        fingerprint = params['fp'];
      }

      return ServerProfile(
        name: name.toUpperCase(),
        address: address,
        port: port,
        protocol: 'VLESS',
        uuid: uuid,
        path: path,
        host: host,
        security: security,
        transportType: transportType,
        publicKey: publicKey,
        shortId: shortId,
        flow: flow,
        fingerprint: fingerprint,
        rawLink: link,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse Hysteria2 link: hysteria2://password@server:port?params#name
  static ServerProfile? fromHysteria2Link(String link) {
    try {
      String withoutScheme;
      if (link.startsWith('hysteria2://')) {
        withoutScheme = link.substring(12);
      } else if (link.startsWith('hy2://')) {
        withoutScheme = link.substring(6);
      } else {
        return null;
      }

      final hashIndex = withoutScheme.indexOf('#');
      final name = hashIndex != -1
          ? Uri.decodeComponent(withoutScheme.substring(hashIndex + 1))
          : 'Hysteria2 Server';

      final mainPart = hashIndex != -1
          ? withoutScheme.substring(0, hashIndex)
          : withoutScheme;

      final atIndex = mainPart.indexOf('@');
      if (atIndex == -1) return null;

      final password = Uri.decodeComponent(mainPart.substring(0, atIndex));
      final rest = mainPart.substring(atIndex + 1);

      final queryIndex = rest.indexOf('?');
      final hostPort = queryIndex != -1
          ? rest.substring(0, queryIndex)
          : rest;

      String address;
      int port;
      if (hostPort.startsWith('[')) {
        final closeBracket = hostPort.indexOf(']');
        if (closeBracket == -1) return null;
        address = hostPort.substring(1, closeBracket);
        final portPart = hostPort.substring(closeBracket + 1);
        port = portPart.startsWith(':')
            ? int.tryParse(portPart.substring(1)) ?? 443
            : 443;
      } else {
        final colonIndex = hostPort.lastIndexOf(':');
        if (colonIndex == -1) return null;
        address = hostPort.substring(0, colonIndex);
        port = int.tryParse(hostPort.substring(colonIndex + 1)) ?? 443;
      }

      String? sni;
      String? obfsType;
      String? obfsPassword;
      int? upMbps;
      int? downMbps;
      bool insecure = false;

      if (queryIndex != -1) {
        final params = Uri.splitQueryString(rest.substring(queryIndex + 1));
        sni = params['sni'] ?? params['peer'];
        obfsType = params['obfs'];
        obfsPassword = params['obfs-password'];
        insecure = params['insecure'] == '1' || params['insecure'] == 'true';
        if (params['upmbps'] != null) upMbps = int.tryParse(params['upmbps']!);
        if (params['downmbps'] != null) downMbps = int.tryParse(params['downmbps']!);
      }

      return ServerProfile(
        name: name.toUpperCase(),
        address: address,
        port: port,
        protocol: 'HYSTERIA2',
        password: password,
        sni: sni,
        obfsType: obfsType,
        obfsPassword: obfsPassword,
        upMbps: upMbps,
        downMbps: downMbps,
        insecure: insecure,
        rawLink: link,
      );
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'server': address,
      'port': port,
      'protocol': protocol,
      'uuid': uuid,
      'path': path,
      'host': host ?? sni ?? address,
      'security': security,
      'transportType': transportType,
      'publicKey': publicKey,
      'shortId': shortId,
      'flow': flow,
      'fingerprint': fingerprint,
      'sni': sni,
      'password': password,
      'obfsType': obfsType,
      'obfsPassword': obfsPassword,
      'upMbps': upMbps,
      'downMbps': downMbps,
      'insecure': insecure,
    };
  }
}
