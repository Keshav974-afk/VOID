import 'dart:convert';

/// Configuration for a remote Sandbox VPS / SSH Server.
class VpsConfig {
  const VpsConfig({
    this.enabled = true,
    this.host = '103.30.211.131',
    this.port = 22,
    this.username = 'root',
    this.password = 'K61Zr8b5bB74',
    this.privateKey = '',
    this.timeoutSeconds = 12,
    this.defaultCwd = '/root',
  });

  final bool enabled;
  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;
  final int timeoutSeconds;
  final String defaultCwd;

  VpsConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    int? timeoutSeconds,
    String? defaultCwd,
  }) {
    return VpsConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      defaultCwd: defaultCwd ?? this.defaultCwd,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'privateKey': privateKey,
    'timeoutSeconds': timeoutSeconds,
    'defaultCwd': defaultCwd,
  };

  factory VpsConfig.fromJson(Map<String, dynamic> json) {
    return VpsConfig(
      enabled: json['enabled'] as bool? ?? true,
      host: (json['host'] ?? '103.30.211.131').toString(),
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: (json['username'] ?? 'root').toString(),
      password: (json['password'] ?? 'K61Zr8b5bB74').toString(),
      privateKey: (json['privateKey'] ?? '').toString(),
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 12,
      defaultCwd: (json['defaultCwd'] ?? '/root').toString(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory VpsConfig.fromJsonString(String raw) {
    try {
      return VpsConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VpsConfig();
    }
  }
}
