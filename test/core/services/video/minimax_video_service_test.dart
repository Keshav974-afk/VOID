import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/video/minimax_video_service.dart';

void main() {
  group('MiniMaxVideoService', () {
    test('MiniMaxVideoResult parsing success and json', () {
      const result = MiniMaxVideoResult(
        status: 'success',
        taskId: '12345678',
        fileId: 'file-999',
        downloadUrl: 'https://cdn.example.com/video.mp4',
        localPath: '/storage/video.mp4',
      );
      expect(result.taskId, '12345678');
      expect(result.status, 'success');
      expect(result.fileId, 'file-999');
      expect(result.downloadUrl, 'https://cdn.example.com/video.mp4');
      expect(result.localPath, '/storage/video.mp4');
      expect(result.isSuccess, isTrue);

      final json = result.toJson();
      expect(json['status'], 'success');
      expect(json['task_id'], '12345678');
      expect(json['download_url'], 'https://cdn.example.com/video.mp4');
    });

    test('MiniMaxVideoResult failure state', () {
      const result = MiniMaxVideoResult(
        status: 'failed',
        error: 'Task timed out',
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'Task timed out');
      expect(result.toJson()['error'], 'Task timed out');
    });
  });
}
