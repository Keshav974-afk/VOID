import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:Kelivo/core/services/tts/sherpa_tts_model_manager.dart';

void main() {
  group('SherpaTtsModelManager', () {
    test('catalog contains Kokoro-82M and Piper VITS models', () {
      final manager = SherpaTtsModelManager();
      expect(manager.catalog.length, greaterThanOrEqualTo(3));

      final kokoro = manager.modelById('kokoro-en-v0_19');
      expect(kokoro.name, contains('Kokoro 82M'));
      expect(kokoro.architecture, SherpaTtsArchitecture.kokoro);
      expect(kokoro.modelFile, 'model.onnx');
      expect(kokoro.voicesFile, 'voices.bin');

      final piperAmy = manager.modelById('vits-piper-en_US-amy-medium-int8');
      expect(piperAmy.name, contains('Amy'));
      expect(piperAmy.architecture, SherpaTtsArchitecture.vits);
    });

    test('validates model directory missing files as false', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_test_');
      try {
        final manager = SherpaTtsModelManager(modelsRoot: tempDir);
        final kokoro = manager.modelById('kokoro-en-v0_19');
        final isValid = await manager.validateModelDirectory(kokoro, tempDir);
        expect(isValid, isFalse);

        // Create the files
        await File(p.join(tempDir.path, 'model.onnx')).writeAsString('fake');
        await File(p.join(tempDir.path, 'voices.bin')).writeAsString('fake');
        await File(p.join(tempDir.path, 'tokens.txt')).writeAsString('fake');
        await Directory(p.join(tempDir.path, 'espeak-ng-data')).create();

        final isValidNow = await manager.validateModelDirectory(
          kokoro,
          tempDir,
        );
        expect(isValidNow, isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
