import 'dart:io';

import 'package:Kelivo/core/services/vision/mirage_vision_model_manager.dart';
import 'package:Kelivo/core/services/vision/mirage_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MirageVisionModelDefinition & Catalog', () {
    test('Mirage catalog contains mirage-22m model definition', () {
      final model = MirageVisionCatalog.mirage22m;
      expect(model.id, equals('mirage-22m'));
      expect(model.name, contains('Mirage 22M'));
      expect(model.vendor, equals('Cactus Compute'));
      expect(model.downloadBytes, equals(23068672));
      expect(model.weightsFile, equals('mirage.safetensors'));
      expect(model.weightsUri.host, equals('huggingface.co'));
    });
  });

  group('MirageVisionModelManager', () {
    late Directory tempDir;
    late MirageVisionModelManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mirage_test_');
      manager = MirageVisionModelManager(modelsRoot: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reports not installed when directory is empty', () async {
      final installed = await manager.isInstalled();
      expect(installed, isFalse);

      final status = await manager.status();
      expect(status.isInstalled, isFalse);
      expect(status.state, equals(MirageVisionInstallState.notInstalled));
    });

    test('reports installed when weights file exceeds threshold', () async {
      final modelDir = await manager.modelDirectory();
      await modelDir.create(recursive: true);
      final weightsFile = File('${modelDir.path}/${manager.model.weightsFile}');

      // Create dummy file > 15 MB
      final sink = weightsFile.openWrite();
      final chunk = List<int>.filled(1024 * 1024, 0); // 1 MB
      for (var i = 0; i < 16; i++) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      final installed = await manager.isInstalled();
      expect(installed, isTrue);

      final status = await manager.status();
      expect(status.isInstalled, isTrue);
      expect(status.state, equals(MirageVisionInstallState.installed));

      // Test deletion
      await manager.deleteModel();
      expect(await manager.isInstalled(), isFalse);
    });
  });

  group('MirageVisionResult', () {
    test('formats markdown output accurately', () {
      const result = MirageVisionResult(
        sceneDescription: 'A landscape photograph with clear blue sky.',
        detectedObjects: ['sky', 'tree', 'mountain'],
        extractedText: 'SAMPLE TEXT OCR',
        executionTimeMs: 42,
        modelId: 'mirage-22m',
      );

      final md = result.toMarkdown();
      expect(md, contains('### 👁️ Mirage 22M Vision Analysis'));
      expect(md, contains('Scene Summary'));
      expect(md, contains('mountain'));
      expect(md, contains('SAMPLE TEXT OCR'));
    });
  });
}
