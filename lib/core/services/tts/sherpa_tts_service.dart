import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'sherpa_tts_model_manager.dart';

final class _TtsSynthesisRequest {
  const _TtsSynthesisRequest({
    required this.architecture,
    required this.directoryPath,
    required this.modelFile,
    this.voicesFile,
    required this.tokensFile,
    required this.dataDir,
    required this.text,
    required this.outputPath,
    required this.speed,
    required this.speakerId,
  });

  final SherpaTtsArchitecture architecture;
  final String directoryPath;
  final String modelFile;
  final String? voicesFile;
  final String tokensFile;
  final String dataDir;
  final String text;
  final String outputPath;
  final double speed;
  final int speakerId;
}

final class SherpaTtsService {
  SherpaTtsService({SherpaTtsModelManager? modelManager})
    : modelManager = modelManager ?? SherpaTtsModelManager();

  final SherpaTtsModelManager modelManager;

  Future<String> synthesizeToWavFile({
    required String modelId,
    required String text,
    required String outputPath,
    double speed = 1.0,
    int speakerId = 0,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Cannot be empty');
    }

    final model = modelManager.modelById(modelId);
    final dir = await modelManager.modelDirectory(modelId);
    if (!await modelManager.validateModelDirectory(model, dir)) {
      throw StateError('TTS Model is not installed: $modelId');
    }

    final request = _TtsSynthesisRequest(
      architecture: model.architecture,
      directoryPath: dir.path,
      modelFile: model.modelFile,
      voicesFile: model.voicesFile,
      tokensFile: model.tokensFile,
      dataDir: model.dataDir,
      text: cleanText,
      outputPath: outputPath,
      speed: speed,
      speakerId: speakerId,
    );

    return await Isolate.run(() => _synthesize(request));
  }

  static String _synthesize(_TtsSynthesisRequest req) {
    sherpa.initBindings();

    sherpa.OfflineTtsConfig config;
    final modelPath = p.join(req.directoryPath, req.modelFile);
    final tokensPath = p.join(req.directoryPath, req.tokensFile);
    final dataDirPath = p.join(req.directoryPath, req.dataDir);

    switch (req.architecture) {
      case SherpaTtsArchitecture.kokoro:
        final voicesPath = req.voicesFile != null
            ? p.join(req.directoryPath, req.voicesFile!)
            : '';
        config = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: modelPath,
              voices: voicesPath,
              tokens: tokensPath,
              dataDir: dataDirPath,
            ),
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          ),
        );
      case SherpaTtsArchitecture.vits:
        config = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: modelPath,
              tokens: tokensPath,
              dataDir: dataDirPath,
            ),
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          ),
        );
    }

    final tts = sherpa.OfflineTts(config);
    try {
      final audio = tts.generate(
        text: req.text,
        sid: req.speakerId,
        speed: req.speed,
      );

      final ok = sherpa.writeWave(
        filename: req.outputPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );

      if (!ok) {
        throw Exception('Failed to write WAV output file');
      }

      return req.outputPath;
    } finally {
      tts.free();
    }
  }
}
