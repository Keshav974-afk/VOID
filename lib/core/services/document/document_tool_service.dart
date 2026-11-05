import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../chat/document_text_extractor.dart';

/// Result of a document tool operation.
class DocumentToolResult {
  const DocumentToolResult({
    required this.status,
    this.text,
    this.outputPath,
    this.pageCount,
    this.error,
  });

  final String status;
  final String? text;
  final String? outputPath;
  final int? pageCount;
  final String? error;

  Map<String, dynamic> toJson() => {
    'status': status,
    if (text != null) 'text': text,
    if (outputPath != null) 'output_path': outputPath,
    if (pageCount != null) 'page_count': pageCount,
    if (error != null) 'error': error,
  };

  String toJsonString() => jsonEncode(toJson());

  static DocumentToolResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (!decoded.containsKey('status') &&
          !decoded.containsKey('output_path') &&
          !decoded.containsKey('filePath')) {
        return null;
      }
      return DocumentToolResult(
        status: (decoded['status'] ?? 'success').toString(),
        text: decoded['text']?.toString(),
        outputPath: (decoded['output_path'] ?? decoded['filePath'])?.toString(),
        pageCount: (decoded['page_count'] as num?)?.toInt(),
        error: decoded['error']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Service that creates, merges, and inspects PDF and text/office documents.
class DocumentToolService {
  const DocumentToolService._();

  static Future<String> _resolveWritablePath(
    String? raw, {
    String defaultFilename = 'document.pdf',
  }) async {
    String filename = (raw ?? '').trim();
    if (filename.isEmpty || filename == '.' || filename == '/') {
      filename = defaultFilename;
    }

    // If filename has a unix root slash like "/document.pdf" or is relative
    if (filename.startsWith('/') &&
        !filename.startsWith('/data/') &&
        !filename.startsWith('/storage/')) {
      filename = filename.substring(1);
    }

    if (!p.isAbsolute(filename)) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        filename = p.join(docsDir.path, filename);
      } catch (_) {
        try {
          final tempDir = await getTemporaryDirectory();
          filename = p.join(tempDir.path, filename);
        } catch (_) {}
      }
    }

    return filename;
  }

  static Future<String> execute(Map<String, dynamic> args) async {
    var action = (args['action'] ?? '').toString().toLowerCase();
    if (action.isEmpty) {
      if (args.containsKey('content') || args.containsKey('text')) {
        action = 'create_pdf';
      } else if (args.containsKey('file_paths')) {
        action = 'merge_pdfs';
      } else {
        action = 'extract_text';
      }
    }

    try {
      switch (action) {
        case 'extract_text':
          final filePath = (args['file_path'] ?? args['path'] ?? '').toString();
          if (filePath.isEmpty) {
            return const DocumentToolResult(
              status: 'error',
              error: 'file_path argument is required for extract_text.',
            ).toJsonString();
          }
          final file = File(filePath);
          if (!await file.exists()) {
            return DocumentToolResult(
              status: 'error',
              error: 'File does not exist: $filePath',
            ).toJsonString();
          }
          final ext = p.extension(filePath).toLowerCase();
          final mime = switch (ext) {
            '.pdf' => 'application/pdf',
            '.docx' =>
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            '.pptx' =>
              'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            '.xlsx' =>
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            _ => 'text/plain',
          };
          final text = await DocumentTextExtractor.extract(
            path: filePath,
            mime: mime,
          );
          return DocumentToolResult(
            status: 'success',
            text: text,
          ).toJsonString();

        case 'create_pdf':
          final content = (args['content'] ?? args['text'] ?? '').toString();
          final title = (args['title'] ?? 'Document').toString();
          final defaultName =
              '${title.replaceAll(RegExp(r'[^\w\-]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final outputPath = await _resolveWritablePath(
            (args['output_path'] ?? args['path'] ?? defaultName).toString(),
            defaultFilename: defaultName,
          );

          final outFile = File(outputPath);
          await outFile.parent.create(recursive: true);

          final document = PdfDocument();
          final page = document.pages.add();
          final graphics = page.graphics;
          final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
          final titleFont = PdfStandardFont(
            PdfFontFamily.helvetica,
            18,
            style: PdfFontStyle.bold,
          );

          graphics.drawString(
            title,
            titleFont,
            bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 30),
          );

          final textElement = PdfTextElement(
            text: content,
            font: font,
            format: PdfStringFormat(lineSpacing: 2),
          );

          final layoutFormat = PdfLayoutFormat(
            layoutType: PdfLayoutType.paginate,
            breakType: PdfLayoutBreakType.fitPage,
          );

          textElement.draw(
            page: page,
            bounds: Rect.fromLTWH(
              0,
              40,
              page.getClientSize().width,
              page.getClientSize().height - 40,
            ),
            format: layoutFormat,
          );

          final bytes = await document.save();
          final pageCount = document.pages.count;
          document.dispose();

          await outFile.writeAsBytes(bytes);

          return DocumentToolResult(
            status: 'success',
            outputPath: outputPath,
            pageCount: pageCount,
            text:
                'PDF document successfully created at $outputPath with $pageCount page(s).',
          ).toJsonString();

        case 'merge_pdfs':
          final paths =
              (args['file_paths'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          final defaultName =
              'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final outputPath = await _resolveWritablePath(
            (args['output_path'] ?? defaultName).toString(),
            defaultFilename: defaultName,
          );

          if (paths.length < 2) {
            return const DocumentToolResult(
              status: 'error',
              error: 'At least two PDF file paths are required for merge.',
            ).toJsonString();
          }

          final finalDoc = PdfDocument();
          int totalPages = 0;

          for (final p in paths) {
            final f = File(p);
            if (!await f.exists()) continue;
            final srcDoc = PdfDocument(inputBytes: await f.readAsBytes());
            final count = srcDoc.pages.count;
            for (int i = 0; i < count; i++) {
              final template = srcDoc.pages[i].createTemplate();
              final page = finalDoc.pages.add();
              page.graphics.drawPdfTemplate(template, const Offset(0, 0));
              totalPages++;
            }
            srcDoc.dispose();
          }

          final outBytes = await finalDoc.save();
          finalDoc.dispose();

          final outFile = File(outputPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(outBytes);

          return DocumentToolResult(
            status: 'success',
            outputPath: outputPath,
            pageCount: totalPages,
            text: 'Successfully merged $totalPages page(s) into $outputPath.',
          ).toJsonString();

        default:
          return DocumentToolResult(
            status: 'error',
            error:
                'Unknown action: $action. Supported actions: extract_text, create_pdf, merge_pdfs.',
          ).toJsonString();
      }
    } catch (e) {
      return DocumentToolResult(
        status: 'error',
        error: e.toString(),
      ).toJsonString();
    }
  }
}
