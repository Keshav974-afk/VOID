import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';

enum SherpaTtsArchitecture { kokoro, vits }

final class SherpaTtsModelDefinition {
  const SherpaTtsModelDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.architecture,
    required this.archiveUri,
    required this.downloadBytes,
    required this.archiveRoot,
    required this.requiredFiles,
    required this.modelFile,
    this.voicesFile,
    this.tokensFile = 'tokens.txt',
    this.dataDir = 'espeak-ng-data',
  });

  final String id;
  final String name;
  final String description;
  final SherpaTtsArchitecture architecture;
  final Uri archiveUri;
  final int downloadBytes;
  final String archiveRoot;
  final List<String> requiredFiles;
  final String modelFile;
  final String? voicesFile;
  final String tokensFile;
  final String dataDir;
}

abstract final class SherpaTtsModelCatalog {
  static final List<SherpaTtsModelDefinition> models = List.unmodifiable([
    SherpaTtsModelDefinition(
      id: 'kokoro-en-v0_19',
      name: 'Kokoro 82M English (Ultra Realistic)',
      description:
          '#1 ranked open-source TTS. Human-grade natural cadence and breathing, ~86 MB.',
      architecture: SherpaTtsArchitecture.kokoro,
      archiveUri: Uri.parse(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'kokoro-en-v0_19.tar.bz2',
      ),
      downloadBytes: 90000000,
      archiveRoot: 'kokoro-en-v0_19',
      requiredFiles: ['model.onnx', 'voices.bin', 'tokens.txt'],
      modelFile: 'model.onnx',
      voicesFile: 'voices.bin',
      tokensFile: 'tokens.txt',
      dataDir: 'espeak-ng-data',
    ),
    SherpaTtsModelDefinition(
      id: 'vits-piper-en_US-amy-medium-int8',
      name: 'Piper VITS Amy (Fast & Crisp)',
      description:
          'Ultra-lightweight natural American voice. Only 20 MB download, instant CPU synthesis.',
      architecture: SherpaTtsArchitecture.vits,
      archiveUri: Uri.parse(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-amy-medium-int8.tar.bz2',
      ),
      downloadBytes: 21076377,
      archiveRoot: 'vits-piper-en_US-amy-medium-int8',
      requiredFiles: ['en_US-amy-medium.onnx', 'tokens.txt'],
      modelFile: 'en_US-amy-medium.onnx',
      tokensFile: 'tokens.txt',
      dataDir: 'espeak-ng-data',
    ),
    SherpaTtsModelDefinition(
      id: 'vits-piper-en_US-lessac-medium-int8',
      name: 'Piper VITS Lessac (Neutral & Clear)',
      description: 'Neutral, clean American English voice. 20 MB download.',
      architecture: SherpaTtsArchitecture.vits,
      archiveUri: Uri.parse(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-lessac-medium-int8.tar.bz2',
      ),
      downloadBytes: 20971520,
      archiveRoot: 'vits-piper-en_US-lessac-medium-int8',
      requiredFiles: ['en_US-lessac-medium.onnx', 'tokens.txt'],
      modelFile: 'en_US-lessac-medium.onnx',
      tokensFile: 'tokens.txt',
      dataDir: 'espeak-ng-data',
    ),
  ]);
}

enum SherpaTtsDownloadPhase { connecting, downloading, extracting, verifying }

final class SherpaTtsDownloadProgress {
  const SherpaTtsDownloadProgress({
    required this.modelId,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String modelId;
  final SherpaTtsDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  int? get percent {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (receivedBytes <= 0) return 0;
    if (receivedBytes >= total) return 100;
    return (receivedBytes * 100) ~/ total;
  }
}

enum SherpaTtsInstallState { notInstalled, downloading, installed, failed }

final class SherpaTtsInstallStatus {
  const SherpaTtsInstallStatus({
    required this.model,
    required this.state,
    this.progress,
    this.error,
  });

  final SherpaTtsModelDefinition model;
  final SherpaTtsInstallState state;
  final SherpaTtsDownloadProgress? progress;
  final String? error;

  bool get isInstalled => state == SherpaTtsInstallState.installed;
}

final class SherpaTtsModelManager {
  SherpaTtsModelManager({
    http.Client? httpClient,
    Directory? modelsRoot,
    List<SherpaTtsModelDefinition>? catalog,
  }) : _httpClient = httpClient ?? http.Client(),
       _injectedModelsRoot = modelsRoot,
       catalog = List.unmodifiable(catalog ?? SherpaTtsModelCatalog.models);

  final http.Client _httpClient;
  final Directory? _injectedModelsRoot;
  final List<SherpaTtsModelDefinition> catalog;
  final Map<String, SherpaTtsDownloadProgress> _activeProgress = {};
  final Map<String, Completer<void>> _activeDownloads = {};
  final Map<String, String> _failures = {};

  Future<Directory> modelsDirectory() async {
    if (_injectedModelsRoot != null) return _injectedModelsRoot;
    final appSupport = await AppDirectories.getAppDataDirectory();
    final dir = Directory(p.join(appSupport.path, 'tts_models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> modelDirectory(String modelId) async {
    final root = await modelsDirectory();
    return Directory(p.join(root.path, modelId));
  }

  SherpaTtsModelDefinition modelById(String modelId) {
    return catalog.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw ArgumentError('Unknown TTS model: $modelId'),
    );
  }

  Future<bool> isInstalled(String modelId) async {
    try {
      final model = modelById(modelId);
      final dir = await modelDirectory(modelId);
      return await validateModelDirectory(model, dir);
    } catch (_) {
      return false;
    }
  }

  Future<bool> validateModelDirectory(
    SherpaTtsModelDefinition model,
    Directory dir,
  ) async {
    if (!await dir.exists()) return false;
    for (final filename in model.requiredFiles) {
      final file = File(p.join(dir.path, filename));
      if (!await file.exists() || await file.length() <= 0) {
        return false;
      }
    }
    return true;
  }

  Future<SherpaTtsInstallStatus> status(String modelId) async {
    final model = modelById(modelId);
    if (_activeDownloads.containsKey(modelId)) {
      return SherpaTtsInstallStatus(
        model: model,
        state: SherpaTtsInstallState.downloading,
        progress: _activeProgress[modelId],
      );
    }
    if (await isInstalled(modelId)) {
      return SherpaTtsInstallStatus(
        model: model,
        state: SherpaTtsInstallState.installed,
      );
    }
    if (_failures.containsKey(modelId)) {
      return SherpaTtsInstallStatus(
        model: model,
        state: SherpaTtsInstallState.failed,
        error: _failures[modelId],
      );
    }
    return SherpaTtsInstallStatus(
      model: model,
      state: SherpaTtsInstallState.notInstalled,
    );
  }

  Future<Directory> downloadModel(
    String modelId, {
    void Function(SherpaTtsDownloadProgress progress)? onProgress,
  }) async {
    final model = modelById(modelId);
    final targetDir = await modelDirectory(modelId);
    if (await validateModelDirectory(model, targetDir)) {
      return targetDir;
    }

    if (_activeDownloads.containsKey(modelId)) {
      await _activeDownloads[modelId]!.future;
      return targetDir;
    }

    final completer = Completer<void>();
    _activeDownloads[modelId] = completer;
    _failures.remove(modelId);

    final tempArchive = File('${targetDir.path}.download.tmp');
    final tempExtract = Directory('${targetDir.path}.extract.tmp');

    try {
      onProgress?.call(
        SherpaTtsDownloadProgress(
          modelId: modelId,
          phase: SherpaTtsDownloadPhase.connecting,
          receivedBytes: 0,
          totalBytes: model.downloadBytes,
        ),
      );

      final candidates = _buildCandidateUris(model.archiveUri);
      var downloaded = false;
      var received = 0;
      int? total = model.downloadBytes;
      Object? lastError;

      for (final candidateUri in candidates) {
        IOSink? sink;
        try {
          if (await tempArchive.exists()) {
            await tempArchive.delete();
          }

          final response = await _sendWithRedirects(candidateUri);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException(
              'HTTP ${response.statusCode} from $candidateUri',
              uri: candidateUri,
            );
          }

          total = response.contentLength ?? model.downloadBytes;
          received = 0;
          sink = tempArchive.openWrite();

          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            final progress = SherpaTtsDownloadProgress(
              modelId: modelId,
              phase: SherpaTtsDownloadPhase.downloading,
              receivedBytes: received,
              totalBytes: total,
            );
            _activeProgress[modelId] = progress;
            onProgress?.call(progress);
          }
          await sink.flush();
          await sink.close();
          sink = null;

          if (received > 0) {
            downloaded = true;
            break;
          }
        } catch (e) {
          lastError = e;
          try {
            await sink?.close();
          } catch (_) {}
          if (await tempArchive.exists()) {
            try {
              await tempArchive.delete();
            } catch (_) {}
          }
        }
      }

      if (!downloaded) {
        throw HttpException(
          'Download failed after trying ${candidates.length} mirrors: $lastError',
        );
      }

      onProgress?.call(
        SherpaTtsDownloadProgress(
          modelId: modelId,
          phase: SherpaTtsDownloadPhase.extracting,
          receivedBytes: received,
          totalBytes: total,
        ),
      );

      if (await tempExtract.exists()) {
        await tempExtract.delete(recursive: true);
      }
      await tempExtract.create(recursive: true);

      // Extract archive in isolate
      await Isolate.run(() async {
        final bytes = await tempArchive.readAsBytes();
        final archive = BZip2Decoder().decodeBytes(bytes);
        final tarArchive = TarDecoder().decodeBytes(archive);
        extractArchiveToDisk(tarArchive, tempExtract.path);
      });

      onProgress?.call(
        SherpaTtsDownloadProgress(
          modelId: modelId,
          phase: SherpaTtsDownloadPhase.verifying,
          receivedBytes: received,
          totalBytes: total,
        ),
      );

      // Locate model root inside extracted dir
      Directory sourceDir = tempExtract;
      final rootCand = Directory(p.join(tempExtract.path, model.archiveRoot));
      if (await rootCand.exists()) {
        sourceDir = rootCand;
      }

      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);

      for (final entity in await sourceDir.list(recursive: true).toList()) {
        final rel = p.relative(entity.path, from: sourceDir.path);
        final destPath = p.join(targetDir.path, rel);
        if (entity is Directory) {
          await Directory(destPath).create(recursive: true);
        } else if (entity is File) {
          await File(destPath).parent.create(recursive: true);
          await entity.copy(destPath);
        }
      }

      if (!await validateModelDirectory(model, targetDir)) {
        throw const FormatException(
          'Extracted files do not match required model schema',
        );
      }

      completer.complete();
      return targetDir;
    } catch (e) {
      _failures[modelId] = e.toString();
      completer.completeError(e);
      rethrow;
    } finally {
      _activeDownloads.remove(modelId);
      _activeProgress.remove(modelId);
      try {
        if (await tempArchive.exists()) {
          await tempArchive.delete();
        }
        if (await tempExtract.exists()) {
          await tempExtract.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> deleteModel(String modelId) async {
    final dir = await modelDirectory(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  List<Uri> _buildCandidateUris(Uri uri) {
    if (!uri.host.contains('github.com')) {
      return [uri];
    }
    return [
      Uri.parse('https://ghproxy.net/$uri'),
      Uri.parse('https://mirror.ghproxy.com/$uri'),
      Uri.parse('https://gh-proxy.com/$uri'),
      uri,
    ];
  }

  Future<http.StreamedResponse> _sendWithRedirects(Uri initialUri) async {
    var currentUri = initialUri;
    const maxRedirects = 5;

    for (var i = 0; i < maxRedirects; i++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
        });

      final response = await _httpClient.send(request);

      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          currentUri = Uri.parse(location);
          continue;
        }
      }

      return response;
    }

    throw const HttpException(
      'Too many redirects while downloading model archive',
    );
  }
}
