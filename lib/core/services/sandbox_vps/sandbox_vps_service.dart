import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/vps_config.dart';

/// Result of a Sandbox VPS operation.
class SandboxVpsToolResult {
  const SandboxVpsToolResult({
    required this.status, // 'success' | 'error'
    required this.action, // 'exec' | 'write_file' | 'read_file' | 'list_dir' | 'status'
    this.host = '',
    this.command,
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.durationMs = 0,
    this.filePath,
    this.fileContent,
    this.entries = const <String>[],
    this.systemInfo,
    this.error,
  });

  final String status;
  final String action;
  final String host;
  final String? command;
  final String stdout;
  final String stderr;
  final int exitCode;
  final int durationMs;
  final String? filePath;
  final String? fileContent;
  final List<String> entries;
  final Map<String, dynamic>? systemInfo;
  final String? error;

  Map<String, dynamic> toJson() => {
    'status': status,
    'action': action,
    'host': host,
    if (command != null) 'command': command,
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'durationMs': durationMs,
    if (filePath != null) 'filePath': filePath,
    if (fileContent != null) 'fileContent': fileContent,
    if (entries.isNotEmpty) 'entries': entries,
    if (systemInfo != null) 'systemInfo': systemInfo,
    if (error != null) 'error': error,
  };

  String toJsonString() => jsonEncode(toJson());

  factory SandboxVpsToolResult.fromJson(Map<String, dynamic> json) {
    return SandboxVpsToolResult(
      status: (json['status'] ?? 'success').toString(),
      action: (json['action'] ?? 'exec').toString(),
      host: (json['host'] ?? '').toString(),
      command: json['command'] as String?,
      stdout: (json['stdout'] ?? '').toString(),
      stderr: (json['stderr'] ?? '').toString(),
      exitCode: (json['exitCode'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String?,
      fileContent: json['fileContent'] as String?,
      entries:
          (json['entries'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      systemInfo: (json['systemInfo'] as Map?)?.cast<String, dynamic>(),
      error: json['error'] as String?,
    );
  }

  static SandboxVpsToolResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (!decoded.containsKey('action')) return null;
      return SandboxVpsToolResult.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// Service that connects to and executes commands inside a remote Linux Sandbox VPS.
class SandboxVpsService {
  SandboxVpsService._();
  static final SandboxVpsService instance = SandboxVpsService._();

  Future<SSHClient> _connect(VpsConfig config) async {
    final timeout = Duration(seconds: config.timeoutSeconds);
    final socket = await SSHSocket.connect(
      config.host,
      config.port,
      timeout: timeout,
    );

    return SSHClient(
      socket,
      username: config.username,
      onPasswordRequest: () => config.password,
    );
  }

  /// Ping/test SSH connection to the VPS.
  Future<Map<String, dynamic>> testConnection(VpsConfig config) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;
      final session = await client.execute('uname -a && whoami');
      final stdoutChunks = <List<int>>[];
      final sub = session.stdout.listen(stdoutChunks.add);
      await session.waitForExit(timeout: const Duration(seconds: 10));
      session.close();
      await session.done.timeout(const Duration(seconds: 2), onTimeout: () {});
      await sub.cancel();
      stopwatch.stop();
      final stdout = utf8.decode(
        stdoutChunks.expand((e) => e).toList(),
        allowMalformed: true,
      );
      return {
        'ok': true,
        'host': config.host,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'info': stdout.trim(),
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'ok': false,
        'host': config.host,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'error': e.toString(),
      };
    } finally {
      client?.close();
    }
  }

  /// Run an arbitrary shell command on the VPS.
  Future<SandboxVpsToolResult> executeCommand({
    required VpsConfig config,
    required String command,
    String? cwd,
    int? timeoutSeconds,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;

      final workingDir = cwd ?? config.defaultCwd;
      final fullCommand = 'cd "$workingDir" 2>/dev/null || true; $command';

      final session = await client.execute(fullCommand);
      final stdoutChunks = <List<int>>[];
      final stderrChunks = <List<int>>[];

      final outSub = session.stdout.listen(stdoutChunks.add);
      final errSub = session.stderr.listen(stderrChunks.add);

      final timeout = Duration(
        seconds: timeoutSeconds ?? config.timeoutSeconds,
      );
      final exitCode = await session.waitForExit(timeout: timeout);
      session.close();
      await session.done.timeout(const Duration(seconds: 2), onTimeout: () {});
      await outSub.cancel();
      await errSub.cancel();
      stopwatch.stop();

      final stdoutText = utf8.decode(
        stdoutChunks.expand((e) => e).toList(),
        allowMalformed: true,
      );
      final stderrText = utf8.decode(
        stderrChunks.expand((e) => e).toList(),
        allowMalformed: true,
      );

      final code = exitCode ?? session.exitCode ?? 0;
      return SandboxVpsToolResult(
        status: code == 0 ? 'success' : 'error',
        action: 'exec',
        host: config.host,
        command: command,
        stdout: stdoutText,
        stderr: stderrText,
        exitCode: code,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      // Local fallback for curl/http operations when remote SSH is unreachable
      if (_isCurlCommand(command)) {
        try {
          final localRes = await _executeCurlLocally(command);
          stopwatch.stop();
          return SandboxVpsToolResult(
            status: 'success',
            action: 'exec',
            host: 'local_fallback',
            command: command,
            stdout: localRes,
            exitCode: 0,
            durationMs: stopwatch.elapsedMilliseconds,
          );
        } catch (_) {}
      }

      stopwatch.stop();
      return SandboxVpsToolResult(
        status: 'error',
        action: 'exec',
        host: config.host,
        command: command,
        exitCode: -1,
        durationMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  bool _isCurlCommand(String cmd) {
    final lower = cmd.trim().toLowerCase();
    return lower.startsWith('curl') || lower.contains('curl ');
  }

  Future<String> _executeCurlLocally(String command) async {
    final urlMatch = RegExp(r'''(?:https?://[^\s"'>]+)''').firstMatch(command);
    if (urlMatch == null) {
      throw StateError('No URL found in curl command');
    }
    final rawUrl = urlMatch.group(0)!;
    final uri = Uri.parse(rawUrl);

    final headers = <String, String>{};
    final headerMatches = RegExp(
      r'''(?:-H|--header)\s+["']?([^"'\r\n]+)["']?''',
    ).allMatches(command);
    for (final m in headerMatches) {
      final headerStr = m.group(1) ?? '';
      final colonIdx = headerStr.indexOf(':');
      if (colonIdx > 0) {
        final key = headerStr.substring(0, colonIdx).trim();
        final val = headerStr.substring(colonIdx + 1).trim();
        headers[key] = val;
      }
    }

    String method = 'GET';
    final methodMatch = RegExp(r'''-X\s+([A-Z]+)''').firstMatch(command);
    if (methodMatch != null) {
      method = methodMatch.group(1)!;
    }

    String? body;
    final bodyMatch = RegExp(
      r'''(?:-d|--data|--data-raw)\s+["']([^"']+)["']''',
    ).firstMatch(command);
    if (bodyMatch != null) {
      body = bodyMatch.group(1);
      if (method == 'GET') method = 'POST';
    }

    final client = http.Client();
    try {
      final request = http.Request(method, uri);
      request.headers.addAll(headers);
      if (body != null) {
        request.body = body;
      }
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      return response.body;
    } finally {
      client.close();
    }
  }

  /// Write a file directly to the remote VPS.
  Future<SandboxVpsToolResult> writeFile({
    required VpsConfig config,
    required String remotePath,
    required String content,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;

      final sftp = await client.sftp();
      final file = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );

      final bytes = Uint8List.fromList(utf8.encode(content));
      await file.write(Stream.value(bytes));
      await file.close();
      stopwatch.stop();

      return SandboxVpsToolResult(
        status: 'success',
        action: 'write_file',
        host: config.host,
        filePath: remotePath,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return SandboxVpsToolResult(
        status: 'error',
        action: 'write_file',
        host: config.host,
        filePath: remotePath,
        durationMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  /// Read a file from the remote VPS.
  Future<SandboxVpsToolResult> readFile({
    required VpsConfig config,
    required String remotePath,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;

      final sftp = await client.sftp();
      final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      final stream = file.read();
      final chunks = <List<int>>[];
      await for (final chunk in stream) {
        chunks.add(chunk);
      }
      await file.close();
      stopwatch.stop();

      final content = utf8.decode(
        chunks.expand((e) => e).toList(),
        allowMalformed: true,
      );
      return SandboxVpsToolResult(
        status: 'success',
        action: 'read_file',
        host: config.host,
        filePath: remotePath,
        fileContent: content,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return SandboxVpsToolResult(
        status: 'error',
        action: 'read_file',
        host: config.host,
        filePath: remotePath,
        durationMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  /// List directories and files on the remote VPS.
  Future<SandboxVpsToolResult> listDir({
    required VpsConfig config,
    required String remotePath,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;

      final sftp = await client.sftp();
      final items = await sftp.listdir(remotePath);
      final entries = items
          .map((e) => '${e.filename}${e.attr.isDirectory ? '/' : ''}')
          .toList();
      stopwatch.stop();

      return SandboxVpsToolResult(
        status: 'success',
        action: 'list_dir',
        host: config.host,
        filePath: remotePath,
        entries: entries,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return SandboxVpsToolResult(
        status: 'error',
        action: 'list_dir',
        host: config.host,
        filePath: remotePath,
        durationMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  /// Query system status (CPU, memory, disk, uptime, OS) on the remote VPS.
  Future<SandboxVpsToolResult> getSystemStatus({
    required VpsConfig config,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    try {
      client = await _connect(config);
      await client.authenticated;

      final script = '''
echo "---OS---"
cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || uname -srm
echo "---UPTIME---"
uptime
echo "---MEM---"
free -h 2>/dev/null || free -m
echo "---DISK---"
df -h /
echo "---PROC---"
ps aux --sort=-%mem 2>/dev/null | head -n 6 || ps | head -n 6
''';
      final session = await client.execute(script);
      final stdoutChunks = <List<int>>[];
      final sub = session.stdout.listen(stdoutChunks.add);
      await session.waitForExit(timeout: const Duration(seconds: 10));
      session.close();
      await session.done.timeout(const Duration(seconds: 2), onTimeout: () {});
      await sub.cancel();
      stopwatch.stop();

      final out = utf8.decode(
        stdoutChunks.expand((e) => e).toList(),
        allowMalformed: true,
      );

      final info = <String, dynamic>{
        'raw': out.trim(),
        'host': config.host,
        'user': config.username,
      };

      return SandboxVpsToolResult(
        status: 'success',
        action: 'status',
        host: config.host,
        systemInfo: info,
        stdout: out.trim(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return SandboxVpsToolResult(
        status: 'error',
        action: 'status',
        host: config.host,
        durationMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  /// Download a binary file (PDF, image, document) from the remote VPS to a local path.
  Future<File> downloadBinaryFile({
    required VpsConfig config,
    required String remotePath,
    String? localPath,
  }) async {
    final client = await _connect(config);
    await client.authenticated;
    try {
      final sftp = await client.sftp();
      final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      final stream = file.read();
      final chunks = <List<int>>[];
      await for (final chunk in stream) {
        chunks.add(chunk);
      }
      await file.close();

      String target = localPath ?? '';
      if (target.isEmpty) {
        final docsDir = await getApplicationDocumentsDirectory();
        final filename = p.basename(remotePath);
        target = p.join(docsDir.path, filename);
      }

      final outFile = File(target);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(chunks.expand((e) => e).toList());
      return outFile;
    } finally {
      client.close();
    }
  }
}
