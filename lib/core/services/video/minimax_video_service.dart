import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_directories.dart';

class MiniMaxVideoResult {
  const MiniMaxVideoResult({
    required this.status,
    this.taskId,
    this.fileId,
    this.downloadUrl,
    this.localPath,
    this.error,
  });

  final String status;
  final String? taskId;
  final String? fileId;
  final String? downloadUrl;
  final String? localPath;
  final String? error;

  bool get isSuccess => status == 'success';

  Map<String, dynamic> toJson() => {
    'status': status,
    if (taskId != null) 'task_id': taskId,
    if (fileId != null) 'file_id': fileId,
    if (downloadUrl != null) 'download_url': downloadUrl,
    if (localPath != null) 'local_path': localPath,
    if (error != null) 'error': error,
  };

  String toJsonString() => jsonEncode(toJson());
}

class MiniMaxVideoService {
  MiniMaxVideoService({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const String _defaultBaseUrl = 'https://api.minimaxi.chat/v1';
  static const String _intlBaseUrl = 'https://api.minimax.io/v1';

  /// Retrieves the configured MiniMax API Key from SharedPreferences or environment
  static Future<String?> getStoredApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          prefs.getString('minimax_video_api_key_v1') ??
          prefs.getString('minimax_api_key_v1');
      if (key != null && key.trim().isNotEmpty) return key.trim();

      // Check tts options or provider configs if stored
      final rawProviders = prefs.getString('provider_configs_v1');
      if (rawProviders != null) {
        final list = jsonDecode(rawProviders) as List?;
        if (list != null) {
          for (final item in list) {
            if (item is Map) {
              final id = (item['id'] ?? '').toString().toLowerCase();
              if (id.contains('minimax')) {
                final k = (item['apiKey'] ?? '').toString().trim();
                if (k.isNotEmpty) return k;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveStoredApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('minimax_video_api_key_v1', apiKey.trim());
  }

  /// Submit video generation task (Text-to-Video or Image-to-Video)
  Future<MiniMaxVideoResult> generateVideo({
    required String prompt,
    String? apiKey,
    String model = 'video-01',
    String? firstFrameImage,
    bool promptOptimizer = true,
    bool isInternational = false,
    bool waitForCompletion = true,
    Duration pollInterval = const Duration(seconds: 4),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final effectiveApiKey = apiKey?.trim() ?? await getStoredApiKey();
    if (effectiveApiKey == null || effectiveApiKey.isEmpty) {
      return const MiniMaxVideoResult(
        status: 'error',
        error:
            'MiniMax API key is required. Please provide api_key or configure MiniMax in settings.',
      );
    }

    final baseUrl = isInternational ? _intlBaseUrl : _defaultBaseUrl;
    final url = Uri.parse('$baseUrl/video_generation');

    final body = <String, dynamic>{
      'prompt': prompt,
      'model': model,
      'prompt_optimizer': promptOptimizer,
    };

    if (firstFrameImage != null && firstFrameImage.isNotEmpty) {
      // Support local image file path converted to base64 data URI
      if (!firstFrameImage.startsWith('http://') &&
          !firstFrameImage.startsWith('https://') &&
          !firstFrameImage.startsWith('data:')) {
        final file = File(firstFrameImage);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final b64 = base64Encode(bytes);
          body['first_frame_image'] = 'data:image/jpeg;base64,$b64';
        } else {
          body['first_frame_image'] = firstFrameImage;
        }
      } else {
        body['first_frame_image'] = firstFrameImage;
      }
    }

    try {
      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer $effectiveApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return MiniMaxVideoResult(
          status: 'error',
          error: 'MiniMax API error (${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      if (baseResp != null && (baseResp['status_code'] as num? ?? 0) != 0) {
        return MiniMaxVideoResult(
          status: 'error',
          error:
              'MiniMax error: ${baseResp['status_msg']} (code ${baseResp['status_code']})',
        );
      }

      final taskId = (data['task_id'] ?? '').toString();
      if (taskId.isEmpty) {
        return MiniMaxVideoResult(
          status: 'error',
          error: 'No task_id returned in MiniMax response: ${response.body}',
        );
      }

      if (!waitForCompletion) {
        return MiniMaxVideoResult(status: 'pending', taskId: taskId);
      }

      // Poll for task completion
      return await pollTaskCompletion(
        taskId: taskId,
        apiKey: effectiveApiKey,
        baseUrl: baseUrl,
        pollInterval: pollInterval,
        timeout: timeout,
      );
    } catch (e) {
      return MiniMaxVideoResult(
        status: 'error',
        error: 'Failed to start video generation: $e',
      );
    }
  }

  /// Polls the status of an ongoing video generation task
  Future<MiniMaxVideoResult> pollTaskCompletion({
    required String taskId,
    required String apiKey,
    String baseUrl = _defaultBaseUrl,
    Duration pollInterval = const Duration(seconds: 4),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final queryUrl = Uri.parse(
      '$baseUrl/query/video_generation?task_id=$taskId',
    );

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);

      try {
        final response = await _client.get(
          queryUrl,
          headers: {'Authorization': 'Bearer $apiKey'},
        );

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString();

        if (status.toLowerCase() == 'success') {
          final fileId = (data['file_id'] ?? '').toString();
          if (fileId.isEmpty) {
            return MiniMaxVideoResult(
              status: 'error',
              taskId: taskId,
              error: 'MiniMax task succeeded but file_id was missing',
            );
          }

          // Retrieve download URL and download video to workspace
          final downloadUrl = await _retrieveFileDownloadUrl(
            fileId: fileId,
            apiKey: apiKey,
            baseUrl: baseUrl,
          );

          String? localPath;
          if (downloadUrl != null) {
            localPath = await _downloadVideoToDisk(downloadUrl, taskId);
          }

          return MiniMaxVideoResult(
            status: 'success',
            taskId: taskId,
            fileId: fileId,
            downloadUrl: downloadUrl,
            localPath: localPath,
          );
        } else if (status.toLowerCase() == 'fail') {
          final baseResp = data['base_resp'] as Map<String, dynamic>?;
          final errorMsg =
              baseResp?['status_msg']?.toString() ?? 'Generation failed';
          return MiniMaxVideoResult(
            status: 'error',
            taskId: taskId,
            error: errorMsg,
          );
        }
      } catch (_) {}
    }

    return MiniMaxVideoResult(
      status: 'timeout',
      taskId: taskId,
      error: 'Timed out waiting for video generation to complete.',
    );
  }

  Future<String?> _retrieveFileDownloadUrl({
    required String fileId,
    required String apiKey,
    String baseUrl = _defaultBaseUrl,
  }) async {
    final url = Uri.parse('$baseUrl/files/retrieve?file_id=$fileId');
    try {
      final response = await _client.get(
        url,
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final file = data['file'] as Map<String, dynamic>?;
        return file?['download_url']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _downloadVideoToDisk(String url, String taskId) async {
    try {
      final supportDir = await AppDirectories.getAppDataDirectory();
      final videosDir = Directory(p.join(supportDir.path, 'generated_videos'));
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }
      final outPath = p.join(videosDir.path, 'minimax_$taskId.mp4');
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await File(outPath).writeAsBytes(response.bodyBytes);
        return outPath;
      }
    } catch (_) {}
    return null;
  }
}
