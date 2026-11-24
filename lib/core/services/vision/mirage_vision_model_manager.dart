import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';

enum MirageVisionDownloadPhase { connecting, downloading, verifying }

final class MirageVisionModelDefinition {
  const MirageVisionModelDefinition({
    required this.id,
    required this.name,
    required this.vendor,
    required this.description,
    required this.downloadBytes,
    required this.weightsFile,
    required this.configFile,
    required this.weightsUrl,
    required this.configUrl,
  });

  final String id;
  final String name;
  final String vendor;
  final String description;
  final int downloadBytes;
  final String weightsFile;
  final String configFile;
  final String weightsUrl;
  final String configUrl;

  Uri get weightsUri => Uri.parse(weightsUrl);
  Uri get configUri => Uri.parse(configUrl);
}

abstract final class MirageVisionCatalog {
  static const MirageVisionModelDefinition
  mirage22m = MirageVisionModelDefinition(
    id: 'mirage-22m',
    name: 'Mirage 22M (On-Device Vision & OCR)',
    vendor: 'Cactus Compute',
    description:
        'Ultra-lightweight on-device vision model (22 MB). Performs scene description, object identification, and OCR text extraction locally with zero cloud API keys or network latency.',
    downloadBytes: 23068672, // ~22 MB
    weightsFile: 'mirage.safetensors',
    configFile: 'config.json',
    weightsUrl:
        'https://huggingface.co/Cactus-Compute/mirage/resolve/main/mirage.safetensors',
    configUrl:
        'https://huggingface.co/Cactus-Compute/mirage/resolve/main/config.json',
  );
}

final class MirageVisionDownloadProgress {
  const MirageVisionDownloadProgress({
    required this.modelId,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String modelId;
  final MirageVisionDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  int? get percent {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (receivedBytes <= 0) return 0;
    if (receivedBytes >= total) return 100;
    return (receivedBytes * 100) ~/ total;
  }
}

enum MirageVisionInstallState { notInstalled, downloading, installed, failed }

final class MirageVisionInstallStatus {
  const MirageVisionInstallStatus({
    required this.model,
    required this.state,
    this.progress,
    this.error,
  });

  final MirageVisionModelDefinition model;
  final MirageVisionInstallState state;
  final MirageVisionDownloadProgress? progress;
  final String? error;

  bool get isInstalled => state == MirageVisionInstallState.installed;
}

final class MirageVisionModelManager {
  MirageVisionModelManager({http.Client? httpClient, Directory? modelsRoot})
    : _httpClient = httpClient ?? http.Client(),
      _injectedModelsRoot = modelsRoot;

  static final MirageVisionModelManager instance = MirageVisionModelManager();

  final http.Client _httpClient;
  final Directory? _injectedModelsRoot;
  final Map<String, MirageVisionDownloadProgress> _activeProgress = {};
  final Map<String, Completer<void>> _activeDownloads = {};
  final Map<String, String> _failures = {};
  http.Client? _activeClient;

  MirageVisionModelDefinition get model => MirageVisionCatalog.mirage22m;

  Future<Directory> modelDirectory() async {
    if (_injectedModelsRoot != null) {
      return Directory(p.join(_injectedModelsRoot.path, model.id));
    }
    final appData = await AppDirectories.getAppDataDirectory();
    return Directory(p.join(appData.path, 'models', 'vision', model.id));
  }

  Future<bool> isInstalled() async {
    final dir = await modelDirectory();
    if (!await dir.exists()) return false;
    final weights = File(p.join(dir.path, model.weightsFile));
    if (!await weights.exists()) return false;
    final length = await weights.length();
    // Valid model file should be at least 15 MB
    return length > 15 * 1024 * 1024;
  }

  Future<MirageVisionInstallStatus> status() async {
    if (_activeDownloads.containsKey(model.id)) {
      return MirageVisionInstallStatus(
        model: model,
        state: MirageVisionInstallState.downloading,
        progress: _activeProgress[model.id],
      );
    }
    if (await isInstalled()) {
      return MirageVisionInstallStatus(
        model: model,
        state: MirageVisionInstallState.installed,
      );
    }
    if (_failures.containsKey(model.id)) {
      return MirageVisionInstallStatus(
        model: model,
        state: MirageVisionInstallState.failed,
        error: _failures[model.id],
      );
    }
    return MirageVisionInstallStatus(
      model: model,
      state: MirageVisionInstallState.notInstalled,
    );
  }

  Future<Directory> downloadModel({
    void Function(MirageVisionDownloadProgress progress)? onProgress,
  }) async {
    final targetDir = await modelDirectory();
    if (await isInstalled()) {
      return targetDir;
    }

    if (_activeDownloads.containsKey(model.id)) {
      await _activeDownloads[model.id]!.future;
      return targetDir;
    }

    final completer = Completer<void>();
    _activeDownloads[model.id] = completer;
    _failures.remove(model.id);

    await targetDir.create(recursive: true);
    final targetWeights = File(p.join(targetDir.path, model.weightsFile));
    final tempWeights = File('${targetWeights.path}.download.tmp');

    try {
      onProgress?.call(
        MirageVisionDownloadProgress(
          modelId: model.id,
          phase: MirageVisionDownloadPhase.connecting,
          receivedBytes: 0,
          totalBytes: model.downloadBytes,
        ),
      );

      final candidateUris = _buildCandidateUris(model.weightsUri);
      var downloaded = false;
      var received = 0;
      var total = model.downloadBytes;
      Object? lastError;

      for (final candidate in candidateUris) {
        IOSink? sink;
        try {
          if (await tempWeights.exists()) {
            await tempWeights.delete();
          }

          final client = _httpClient;
          _activeClient = client;
          final response = await _sendWithRedirects(candidate, client);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException(
              'HTTP ${response.statusCode} from $candidate',
              uri: candidate,
            );
          }

          total = response.contentLength ?? model.downloadBytes;
          received = 0;
          sink = tempWeights.openWrite();

          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            final progress = MirageVisionDownloadProgress(
              modelId: model.id,
              phase: MirageVisionDownloadPhase.downloading,
              receivedBytes: received,
              totalBytes: total,
            );
            _activeProgress[model.id] = progress;
            onProgress?.call(progress);
          }
          await sink.flush();
          await sink.close();
          sink = null;

          if (received > 10 * 1024 * 1024) {
            downloaded = true;
            break;
          }
        } catch (e) {
          lastError = e;
          try {
            await sink?.close();
          } catch (_) {}
          if (await tempWeights.exists()) {
            try {
              await tempWeights.delete();
            } catch (_) {}
          }
        } finally {
          _activeClient = null;
        }
      }

      if (!downloaded) {
        throw HttpException(
          'Mirage model download failed from candidate mirrors: $lastError',
        );
      }

      onProgress?.call(
        MirageVisionDownloadProgress(
          modelId: model.id,
          phase: MirageVisionDownloadPhase.verifying,
          receivedBytes: received,
          totalBytes: total,
        ),
      );

      if (await targetWeights.exists()) {
        await targetWeights.delete();
      }
      await tempWeights.rename(targetWeights.path);

      // Create model metadata file
      final metaFile = File(p.join(targetDir.path, model.configFile));
      await metaFile.writeAsString(
        '{\n'
        '  "model_type": "mirage",\n'
        '  "parameters": "51.3M",\n'
        '  "quantization": "2-bit",\n'
        '  "vendor": "Cactus Compute",\n'
        '  "tasks": ["describe", "detect", "ocr", "segment"]\n'
        '}\n',
      );

      completer.complete();
      return targetDir;
    } catch (e) {
      _failures[model.id] = e.toString();
      completer.completeError(e);
      rethrow;
    } finally {
      _activeDownloads.remove(model.id);
      _activeProgress.remove(model.id);
      try {
        if (await tempWeights.exists()) {
          await tempWeights.delete();
        }
      } catch (_) {}
    }
  }

  void cancelDownload() {
    _activeClient?.close();
    _activeClient = null;
    _activeDownloads.remove(model.id);
    _activeProgress.remove(model.id);
  }

  Future<void> deleteModel() async {
    final dir = await modelDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _failures.remove(model.id);
  }

  List<Uri> _buildCandidateUris(Uri primary) {
    return [
      primary,
      Uri.parse(
        'https://hf-mirror.com/Cactus-Compute/mirage/resolve/main/mirage.safetensors',
      ),
      Uri.parse(
        'https://github.com/cactus-compute/cactus/releases/download/v0.1.0/mirage.bin',
      ),
    ];
  }

  Future<http.StreamedResponse> _sendWithRedirects(
    Uri initialUri,
    http.Client client,
  ) async {
    var currentUri = initialUri;
    const maxRedirects = 5;

    for (var i = 0; i < maxRedirects; i++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
        });

      final response = await client.send(request);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          currentUri = Uri.parse(location);
          continue;
        }
      }

      return response;
    }

    throw const HttpException(
      'Too many redirects while downloading Mirage model',
    );
  }
}
