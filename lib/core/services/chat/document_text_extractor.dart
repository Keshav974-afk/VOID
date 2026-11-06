import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/unicode_sanitizer.dart';

/// Data passed to the background isolate for document extraction.
class _ExtractorParams {
  final String path;
  final String mime;
  _ExtractorParams(this.path, this.mime);
}

class AttachmentRequiresWorkspace implements Exception {
  const AttachmentRequiresWorkspace(this.name);
  final String name;
  @override
  String toString() => 'Attachment requires workspace file tools: $name';
}

class DocumentTextExtractor {
  /// Extracts text from a document file at [path] with [mime] type.
  ///
  /// Resolves via [SandboxPathResolver.resolveForIo] once, then delegates to
  /// [extractResolved]. Prefer [extractResolved] when the caller already
  /// resolved the path (avoid a second pass).
  static Future<String> extract({
    required String path,
    required String mime,
  }) async {
    final resolved = SandboxPathResolver.resolveForIo(path);
    if (resolved == null) return '[[File not found: $path]]';
    return extractResolved(path: resolved, mime: mime);
  }

  /// Extract using an already-resolved absolute filesystem path.
  /// Does **not** call [SandboxPathResolver.fix] / [resolveForIo].
  static Future<String> extractResolved({
    required String path,
    required String mime,
  }) {
    // Offload the heavy work to a separate isolate using compute.
    return compute(_extractTask, _ExtractorParams(path, mime));
  }

  /// The heavy extraction logic that runs in a background isolate.
  static String _extractTask(_ExtractorParams params) {
    final path = params.path;
    final mime = params.mime;

    try {
      final source = File(path);
      if (!source.existsSync()) return '[[File not found: $path]]';
      // Receiving a file is independent of inlining it in a model request.
      // Larger files remain available to workspace tools without a full read.
      if (source.lengthSync() > 16 * 1024 * 1024) {
        throw AttachmentRequiresWorkspace(p.basename(path));
      }
      if (mime == 'application/pdf') {
        try {
          final file = File(path);
          if (!file.existsSync()) return '[[File not found: $path]]';

          final bytes = file.readAsBytesSync();
          // Heavy synchronous PDF parsing happens here, in the sub-thread.
          final document = PdfDocument(inputBytes: bytes);
          final extractor = PdfTextExtractor(document);
          final extracted = extractor.extractText();
          final text = UnicodeSanitizer.sanitize(extracted);

          document.dispose();

          if (text.trim().isNotEmpty) return text;
          return '[PDF] Unable to extract text from file.';
        } catch (e) {
          return '[[Failed to read PDF: $e]]';
        }
      }

      if (mime == 'application/msword') {
        return '[[DOC format (.doc) not supported for text extraction]]';
      }

      if (mime ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
        return _extractDocxSync(path);
      }

      if (mime ==
          'application/vnd.openxmlformats-officedocument.presentationml.presentation') {
        return _extractPptxSync(path);
      }

      if (mime ==
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        return _extractXlsxSync(path);
      }

      final extLower = p.extension(path).toLowerCase();
      if (extLower == '.docx') return _extractDocxSync(path);
      if (extLower == '.pptx') return _extractPptxSync(path);
      if (extLower == '.xlsx') return _extractXlsxSync(path);

      // Unknown types may be archives or executables. Probe a small prefix
      // before deciding whether a text read is useful.
      final probe = source.openSync();
      try {
        final prefix = probe.readSync(8192);
        if (prefix.contains(0)) {
          throw AttachmentRequiresWorkspace(p.basename(path));
        }
        final decoder = utf8.decoder.startChunkedConversion(
          StringConversionSink.fromStringSink(StringBuffer()),
        );
        try {
          decoder.add(prefix);
          if (source.lengthSync() <= prefix.length) decoder.close();
        } on FormatException {
          throw AttachmentRequiresWorkspace(p.basename(path));
        }
      } finally {
        probe.closeSync();
      }
      // Read only bounded, text-like files.
      final file = File(path);
      if (!file.existsSync()) return '[[File not found: $path]]';
      final bytes = file.readAsBytesSync();
      return UnicodeSanitizer.sanitize(
        utf8.decode(bytes, allowMalformed: true),
      );
    } on AttachmentRequiresWorkspace {
      rethrow;
    } catch (e) {
      return '[[Failed to read file: $e]]';
    }
  }

  /// Synchronous DOCX extraction for isolate use.
  static String _extractDocxSync(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '[DOCX] file not found';

      final input = file.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(input);
      final docXml = archive.findFile('word/document.xml');
      if (docXml == null) return '[DOCX] document.xml not found';

      final xml = XmlDocument.parse(utf8.decode(docXml.content as List<int>));
      final buffer = StringBuffer();
      for (final p in xml.findAllElements('w:p')) {
        final texts = p.findAllElements('w:t');
        if (texts.isEmpty) {
          buffer.writeln();
          continue;
        }
        for (final t in texts) {
          buffer.write(t.innerText);
        }
        buffer.writeln();
      }
      return UnicodeSanitizer.sanitize(buffer.toString());
    } catch (e) {
      return '[[Failed to parse DOCX: $e]]';
    }
  }

  /// Synchronous PPTX extraction for isolate use.
  static String _extractPptxSync(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '[PPTX] file not found';

      final input = file.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(input);
      final slideFiles =
          archive.files
              .where(
                (f) =>
                    f.isFile &&
                    f.name.startsWith('ppt/slides/slide') &&
                    f.name.endsWith('.xml'),
              )
              .toList()
            ..sort((a, b) {
              final numA =
                  int.tryParse(
                    RegExp(r'(\d+)').firstMatch(a.name)?.group(1) ?? '',
                  ) ??
                  0;
              final numB =
                  int.tryParse(
                    RegExp(r'(\d+)').firstMatch(b.name)?.group(1) ?? '',
                  ) ??
                  0;
              return numA.compareTo(numB);
            });

      if (slideFiles.isEmpty) return '[PPTX] No slides found';

      final buffer = StringBuffer();
      for (int i = 0; i < slideFiles.length; i++) {
        final sf = slideFiles[i];
        final xml = XmlDocument.parse(utf8.decode(sf.content as List<int>));
        buffer.writeln('## Slide ${i + 1}');
        for (final pNode in xml.findAllElements('a:p')) {
          final texts = pNode
              .findAllElements('a:t')
              .map((t) => t.innerText)
              .join();
          if (texts.trim().isNotEmpty) {
            buffer.writeln('- ${texts.trim()}');
          }
        }
        buffer.writeln();
      }
      return UnicodeSanitizer.sanitize(buffer.toString());
    } catch (e) {
      return '[[Failed to parse PPTX: $e]]';
    }
  }

  /// Synchronous XLSX extraction for isolate use.
  static String _extractXlsxSync(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '[XLSX] file not found';

      final input = file.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(input);

      final sharedStrings = <String>[];
      final ssFile = archive.findFile('xl/sharedStrings.xml');
      if (ssFile != null) {
        final ssXml = XmlDocument.parse(
          utf8.decode(ssFile.content as List<int>),
        );
        for (final si in ssXml.findAllElements('si')) {
          final text = si.findAllElements('t').map((e) => e.innerText).join();
          sharedStrings.add(text);
        }
      }

      final sheetNames = <String>[];
      final wbFile = archive.findFile('xl/workbook.xml');
      if (wbFile != null) {
        final wbXml = XmlDocument.parse(
          utf8.decode(wbFile.content as List<int>),
        );
        for (final s in wbXml.findAllElements('sheet')) {
          final name = s.getAttribute('name');
          if (name != null) sheetNames.add(name);
        }
      }

      final sheetFiles =
          archive.files
              .where(
                (f) =>
                    f.isFile &&
                    f.name.startsWith('xl/worksheets/sheet') &&
                    f.name.endsWith('.xml'),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

      if (sheetFiles.isEmpty) return '[XLSX] No worksheets found';

      final buffer = StringBuffer();
      for (int sIdx = 0; sIdx < sheetFiles.length; sIdx++) {
        final sf = sheetFiles[sIdx];
        final title = sIdx < sheetNames.length
            ? sheetNames[sIdx]
            : 'Sheet ${sIdx + 1}';
        buffer.writeln('### $title');
        final xml = XmlDocument.parse(utf8.decode(sf.content as List<int>));
        for (final row in xml.findAllElements('row')) {
          final cells = <String>[];
          for (final c in row.findAllElements('c')) {
            final tAttr = c.getAttribute('t');
            String val = '';
            if (tAttr == 'inlineStr') {
              val = c.findAllElements('t').map((e) => e.innerText).join();
            } else {
              final vElem = c.findElements('v').firstOrNull;
              final rawV = vElem?.innerText ?? '';
              if (tAttr == 's') {
                final idx = int.tryParse(rawV);
                if (idx != null && idx >= 0 && idx < sharedStrings.length) {
                  val = sharedStrings[idx];
                } else {
                  val = rawV;
                }
              } else {
                val = rawV;
              }
            }
            cells.add(val.replaceAll('|', r'\|').replaceAll('\n', ' '));
          }
          if (cells.any((x) => x.isNotEmpty)) {
            buffer.writeln('| ${cells.join(' | ')} |');
          }
        }
        buffer.writeln();
      }
      return UnicodeSanitizer.sanitize(buffer.toString());
    } catch (e) {
      return '[[Failed to parse XLSX: $e]]';
    }
  }
}
