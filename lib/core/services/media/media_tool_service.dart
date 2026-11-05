import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

/// Result of a media processing operation.
class MediaToolResult {
  const MediaToolResult({
    required this.status,
    this.outputPath,
    this.info,
    this.error,
  });

  final String status;
  final String? outputPath;
  final Map<String, dynamic>? info;
  final String? error;

  Map<String, dynamic> toJson() => {
    'status': status,
    if (outputPath != null) 'output_path': outputPath,
    if (info != null) 'info': info,
    if (error != null) 'error': error,
  };

  String toJsonString() => jsonEncode(toJson());
}

/// Service that performs image/media conversion, resizing, and inspections.
class MediaToolService {
  const MediaToolService._();

  static Future<String> execute(Map<String, dynamic> args) async {
    final action = (args['action'] ?? 'info').toString().toLowerCase();
    final inputPath = (args['input_path'] ?? args['file_path'] ?? '')
        .toString();

    if (inputPath.isEmpty) {
      return const MediaToolResult(
        status: 'error',
        error: 'input_path argument is required.',
      ).toJsonString();
    }

    final file = File(inputPath);
    if (!await file.exists()) {
      return MediaToolResult(
        status: 'error',
        error: 'File does not exist: $inputPath',
      ).toJsonString();
    }

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const MediaToolResult(
          status: 'error',
          error: 'Failed to decode media file or unsupported format.',
        ).toJsonString();
      }

      switch (action) {
        case 'info':
          return MediaToolResult(
            status: 'success',
            info: {
              'width': decoded.width,
              'height': decoded.height,
              'num_frames': decoded.numFrames,
              'has_alpha': decoded.hasAlpha,
              'file_size_bytes': bytes.length,
            },
          ).toJsonString();

        case 'resize':
          final targetWidth = (args['width'] as num?)?.toInt() ?? decoded.width;
          final targetHeight =
              (args['height'] as num?)?.toInt() ?? decoded.height;
          final resized = img.copyResize(
            decoded,
            width: targetWidth,
            height: targetHeight,
          );
          final outPath = (args['output_path'] ?? '').toString().isNotEmpty
              ? args['output_path'].toString()
              : inputPath.replaceFirst(
                  RegExp(r'\.[a-zA-Z0-9]+$'),
                  '_resized.png',
                );
          final encoded = img.encodePng(resized);
          await File(outPath).writeAsBytes(encoded);
          return MediaToolResult(
            status: 'success',
            outputPath: outPath,
            info: {'width': targetWidth, 'height': targetHeight},
          ).toJsonString();

        case 'convert':
          final targetFormat = (args['format'] ?? 'png')
              .toString()
              .toLowerCase();
          List<int> outBytes;
          String ext;
          if (targetFormat == 'jpg' || targetFormat == 'jpeg') {
            outBytes = img.encodeJpg(decoded);
            ext = '.jpg';
          } else if (targetFormat == 'gif') {
            outBytes = img.encodeGif(decoded);
            ext = '.gif';
          } else {
            outBytes = img.encodePng(decoded);
            ext = '.png';
          }
          final outPath = (args['output_path'] ?? '').toString().isNotEmpty
              ? args['output_path'].toString()
              : inputPath.replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), ext);
          await File(outPath).writeAsBytes(outBytes);
          return MediaToolResult(
            status: 'success',
            outputPath: outPath,
            info: {'format': targetFormat, 'size_bytes': outBytes.length},
          ).toJsonString();

        default:
          return MediaToolResult(
            status: 'error',
            error: 'Unknown action: $action. Use info, resize, or convert.',
          ).toJsonString();
      }
    } catch (e) {
      return MediaToolResult(
        status: 'error',
        error: e.toString(),
      ).toJsonString();
    }
  }
}
