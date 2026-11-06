import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive_io.dart';
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

/// Service that creates, merges, and inspects PDF, Word (.docx), Excel (.xlsx),
/// and PowerPoint (.pptx) documents natively on the device.
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

    if (filename.startsWith('/') &&
        !filename.startsWith('/data/') &&
        !filename.startsWith('/storage/') &&
        !filename.startsWith('/Users/') &&
        !filename.startsWith('/home/')) {
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

    final expectedExt = p.extension(defaultFilename).toLowerCase();
    if (expectedExt.isNotEmpty && p.extension(filename).isEmpty) {
      filename = '$filename$expectedExt';
    }

    return filename;
  }

  static Future<String> execute(Map<String, dynamic> args) async {
    var action = (args['action'] ?? '').toString().toLowerCase().trim();
    final rawFormat = (args['format'] ?? '').toString().toLowerCase().trim();
    if (action.isEmpty) {
      if (rawFormat == 'docx' || rawFormat == 'word') {
        action = 'create_docx';
      } else if (rawFormat == 'xlsx' || rawFormat == 'excel') {
        action = 'create_xlsx';
      } else if (rawFormat == 'pptx' ||
          rawFormat == 'powerpoint' ||
          args.containsKey('slides')) {
        action = 'create_pptx';
      } else if (args.containsKey('sheets') || args.containsKey('rows')) {
        action = 'create_xlsx';
      } else if (args.containsKey('content') || args.containsKey('text')) {
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
          return await _handleExtractText(args);
        case 'create_pdf':
        case 'pdf':
          return await _handleCreateAttractivePdf(args);
        case 'create_docx':
        case 'docx':
        case 'word':
          return await _handleCreateDocx(args);
        case 'create_xlsx':
        case 'xlsx':
        case 'excel':
          return await _handleCreateXlsx(args);
        case 'create_pptx':
        case 'pptx':
        case 'powerpoint':
          return await _handleCreatePptx(args);
        case 'merge_pdfs':
          return await _handleMergePdfs(args);
        default:
          return DocumentToolResult(
            status: 'error',
            error:
                'Unknown action: $action. Supported actions: extract_text, create_pdf, create_docx, create_xlsx, create_pptx, merge_pdfs.',
          ).toJsonString();
      }
    } catch (e) {
      return DocumentToolResult(
        status: 'error',
        error: e.toString(),
      ).toJsonString();
    }
  }

  static Future<String> _handleExtractText(Map<String, dynamic> args) async {
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
    return DocumentToolResult(status: 'success', text: text).toJsonString();
  }

  // ---------------------------------------------------------------------------
  // 1. Attractive Styled PDF Generation
  // ---------------------------------------------------------------------------

  static ({PdfColor primary, PdfColor accent, PdfColor lightBg, PdfColor dark})
  _resolvePdfThemePalette(String themeName) {
    switch (themeName.toLowerCase().trim()) {
      case 'emerald':
      case 'green':
        return (
          primary: PdfColor(6, 95, 70),
          accent: PdfColor(16, 185, 129),
          lightBg: PdfColor(236, 253, 245),
          dark: PdfColor(17, 24, 39),
        );
      case 'crimson':
      case 'red':
      case 'rose':
        return (
          primary: PdfColor(153, 27, 27),
          accent: PdfColor(239, 68, 68),
          lightBg: PdfColor(254, 242, 242),
          dark: PdfColor(17, 24, 39),
        );
      case 'royal':
      case 'purple':
      case 'indigo':
        return (
          primary: PdfColor(55, 48, 163),
          accent: PdfColor(99, 102, 241),
          lightBg: PdfColor(238, 242, 255),
          dark: PdfColor(17, 24, 39),
        );
      case 'slate':
      case 'minimal':
        return (
          primary: PdfColor(30, 41, 59),
          accent: PdfColor(71, 85, 105),
          lightBg: PdfColor(241, 245, 249),
          dark: PdfColor(15, 23, 42),
        );
      case 'executive':
      case 'navy':
      case 'ocean':
      default:
        return (
          primary: PdfColor(15, 42, 74),
          accent: PdfColor(2, 132, 199),
          lightBg: PdfColor(240, 249, 255),
          dark: PdfColor(15, 23, 42),
        );
    }
  }

  static String _stripInlineMd(String s) {
    return s
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'__(.+?)__'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .trim();
  }

  static Future<String> _handleCreateAttractivePdf(
    Map<String, dynamic> args,
  ) async {
    final content = (args['content'] ?? args['text'] ?? '').toString();
    final title = (args['title'] ?? 'Document').toString();
    final subtitle = (args['subtitle'] ?? '').toString();
    final author = (args['author'] ?? 'Kelivo Studio').toString();
    final themeName = (args['theme'] ?? 'executive').toString();
    final safeSlug = title
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final defaultName =
        '${safeSlug.isEmpty ? 'document' : safeSlug}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputPath = await _resolveWritablePath(
      (args['output_path'] ?? args['path'] ?? defaultName).toString(),
      defaultFilename: defaultName,
    );

    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);

    final palette = _resolvePdfThemePalette(themeName);
    final document = PdfDocument();
    document.pageSettings.margins.all = 42;

    // Fonts
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      22,
      style: PdfFontStyle.bold,
    );
    final subtitleFont = PdfStandardFont(PdfFontFamily.helvetica, 11.5);
    final h1Font = PdfStandardFont(
      PdfFontFamily.helvetica,
      15.5,
      style: PdfFontStyle.bold,
    );
    final h2Font = PdfStandardFont(
      PdfFontFamily.helvetica,
      13,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10.5);
    final boldBodyFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      10.5,
      style: PdfFontStyle.bold,
    );
    final monoFont = PdfStandardFont(PdfFontFamily.courier, 9.5);
    final metaFont = PdfStandardFont(PdfFontFamily.helvetica, 8.5);

    PdfPage currentPage = document.pages.add();
    final pageWidth = currentPage.getClientSize().width;
    final pageHeight = currentPage.getClientSize().height;
    const footerReserve = 28.0;
    final maxY = pageHeight - footerReserve;

    // Draw modern header banner on Page 1
    final bannerHeight = subtitle.isNotEmpty ? 88.0 : 70.0;
    currentPage.graphics.drawRectangle(
      brush: PdfSolidBrush(palette.primary),
      bounds: Rect.fromLTWH(0, 0, pageWidth, bannerHeight),
    );
    // Accent bar at bottom of header banner
    currentPage.graphics.drawRectangle(
      brush: PdfSolidBrush(palette.accent),
      bounds: Rect.fromLTWH(0, bannerHeight - 4, pageWidth, 4),
    );

    currentPage.graphics.drawString(
      title,
      titleFont,
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(20, 16, pageWidth - 40, 32),
      format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle),
    );

    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final headerSub = subtitle.isNotEmpty ? subtitle : '$author  •  $dateStr';
    currentPage.graphics.drawString(
      headerSub,
      subtitleFont,
      brush: PdfSolidBrush(PdfColor(215, 230, 248)),
      bounds: Rect.fromLTWH(20, 48, pageWidth - 40, 24),
    );

    double y = bannerHeight + 18.0;

    void ensureSpace(double needed) {
      if (y + needed > maxY) {
        currentPage = document.pages.add();
        // Subtle top accent bar on continuation pages
        currentPage.graphics.drawRectangle(
          brush: PdfSolidBrush(palette.accent),
          bounds: Rect.fromLTWH(0, 0, pageWidth, 2.5),
        );
        y = 14.0;
      }
    }

    void drawPaginatedText(
      String text,
      PdfFont font, {
      PdfColor? color,
      double leftIndent = 0,
      double spacingAfter = 8,
    }) {
      if (text.trim().isEmpty) return;
      ensureSpace(22);
      final element = PdfTextElement(
        text: text,
        font: font,
        brush: PdfSolidBrush(color ?? palette.dark),
        format: PdfStringFormat(lineSpacing: 3.5),
      );
      final layoutRes = element.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(leftIndent, y, pageWidth - leftIndent, maxY - y),
        format: PdfLayoutFormat(
          layoutType: PdfLayoutType.paginate,
          breakType: PdfLayoutBreakType.fitPage,
        ),
      );
      if (layoutRes != null) {
        currentPage = layoutRes.page;
        y = layoutRes.bounds.bottom + spacingAfter;
      } else {
        y += 18 + spacingAfter;
      }
    }

    // Parse markdown content into blocks (headings, tables, callouts, code, bullets, paragraphs)
    final lines = content.split(RegExp(r'\r?\n'));
    int i = 0;
    while (i < lines.length) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty) {
        y += 4;
        i++;
        continue;
      }

      // Horizontal Rule
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        ensureSpace(14);
        currentPage.graphics.drawLine(
          PdfPen(PdfColor(203, 213, 225), width: 0.8),
          Offset(0, y + 4),
          Offset(pageWidth, y + 4),
        );
        y += 12;
        i++;
        continue;
      }

      // Markdown Table
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        final tableLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          tableLines.add(lines[i].trim());
          i++;
        }
        final parsedRows = <List<String>>[];
        for (final tl in tableLines) {
          final inner = tl.substring(1, tl.length > 1 ? tl.length - 1 : 1);
          final cells = inner.split('|').map((c) => _stripInlineMd(c)).toList();
          // Skip separator rows like |---|---|
          if (cells.every((c) => RegExp(r'^[:\-\s]*$').hasMatch(c))) {
            continue;
          }
          parsedRows.add(cells);
        }
        if (parsedRows.isNotEmpty) {
          ensureSpace(48);
          final colCount = parsedRows.fold<int>(
            1,
            (m, r) => r.length > m ? r.length : m,
          );
          final grid = PdfGrid();
          grid.columns.add(count: colCount);
          grid.headers.add(1);
          final header = grid.headers[0];
          for (int c = 0; c < colCount; c++) {
            header.cells[c].value = c < parsedRows.first.length
                ? parsedRows.first[c]
                : '';
          }
          header.style = PdfGridRowStyle(
            backgroundBrush: PdfSolidBrush(palette.primary),
            textBrush: PdfSolidBrush(PdfColor(255, 255, 255)),
            font: boldBodyFont,
          );
          for (int r = 1; r < parsedRows.length; r++) {
            final row = grid.rows.add();
            for (int c = 0; c < colCount; c++) {
              row.cells[c].value = c < parsedRows[r].length
                  ? parsedRows[r][c]
                  : '';
            }
            row.style = PdfGridRowStyle(
              backgroundBrush: PdfSolidBrush(
                r.isEven ? palette.lightBg : PdfColor(255, 255, 255),
              ),
              textBrush: PdfSolidBrush(palette.dark),
              font: bodyFont,
            );
          }
          grid.style.cellPadding = PdfPaddings(
            left: 8,
            right: 8,
            top: 6,
            bottom: 6,
          );
          final gridResult = grid.draw(
            page: currentPage,
            bounds: Rect.fromLTWH(0, y, pageWidth, maxY - y),
          );
          if (gridResult != null) {
            currentPage = gridResult.page;
            y = gridResult.bounds.bottom + 12;
          }
        }
        continue;
      }

      // Fenced Code Block
      if (trimmed.startsWith('```')) {
        i++;
        final codeLines = <String>[];
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
        final codeText = codeLines.join('\n');
        if (codeText.trim().isNotEmpty) {
          ensureSpace(36);
          final measured = monoFont.measureString(
            codeText,
            layoutArea: Size(pageWidth - 24, maxY),
          );
          final boxH = (measured.height + 18).clamp(26.0, maxY - y);
          currentPage.graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(241, 245, 249)),
            pen: PdfPen(PdfColor(203, 213, 225), width: 0.6),
            bounds: Rect.fromLTWH(0, y, pageWidth, boxH),
          );
          drawPaginatedText(
            codeText,
            monoFont,
            color: PdfColor(30, 41, 59),
            leftIndent: 10,
            spacingAfter: 12,
          );
        }
        continue;
      }

      // Headings (#, ##, ###)
      if (trimmed.startsWith('# ')) {
        final hText = _stripInlineMd(trimmed.substring(2));
        ensureSpace(34);
        y += 6;
        // Left accent bar for H1
        currentPage.graphics.drawRectangle(
          brush: PdfSolidBrush(palette.accent),
          bounds: Rect.fromLTWH(0, y + 2, 4, 18),
        );
        drawPaginatedText(
          hText,
          h1Font,
          color: palette.primary,
          leftIndent: 10,
          spacingAfter: 6,
        );
        i++;
        continue;
      }
      if (trimmed.startsWith('## ')) {
        final hText = _stripInlineMd(trimmed.substring(3));
        ensureSpace(28);
        y += 4;
        drawPaginatedText(
          hText,
          h2Font,
          color: palette.primary,
          spacingAfter: 5,
        );
        i++;
        continue;
      }
      if (trimmed.startsWith('### ')) {
        final hText = _stripInlineMd(trimmed.substring(4));
        ensureSpace(24);
        drawPaginatedText(
          hText,
          boldBodyFont,
          color: palette.accent,
          spacingAfter: 4,
        );
        i++;
        continue;
      }

      // Blockquote / Callout (> ...)
      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(
            _stripInlineMd(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), '')),
          );
          i++;
        }
        final qText = quoteLines.join('\n');
        ensureSpace(30);
        final startY = y;
        drawPaginatedText(
          qText,
          bodyFont,
          color: palette.primary,
          leftIndent: 12,
          spacingAfter: 8,
        );
        currentPage.graphics.drawRectangle(
          brush: PdfSolidBrush(palette.accent),
          bounds: Rect.fromLTWH(
            0,
            startY,
            3.5,
            (y - startY - 6).clamp(14, 200),
          ),
        );
        continue;
      }

      // Bullet or numbered list
      final bulletMatch = RegExp(
        r'^(\s*)([-*•]|\d+\.)\s+(.*)$',
      ).firstMatch(rawLine);
      if (bulletMatch != null) {
        final marker = bulletMatch.group(2)!;
        final itemText = _stripInlineMd(bulletMatch.group(3)!);
        final displayMarker = (marker == '-' || marker == '*') ? '•' : marker;
        ensureSpace(20);
        currentPage.graphics.drawString(
          displayMarker,
          boldBodyFont,
          brush: PdfSolidBrush(palette.accent),
          bounds: Rect.fromLTWH(6, y, 22, 18),
        );
        drawPaginatedText(itemText, bodyFont, leftIndent: 24, spacingAfter: 5);
        i++;
        continue;
      }

      // Regular paragraph
      drawPaginatedText(_stripInlineMd(trimmed), bodyFont, spacingAfter: 7);
      i++;
    }

    // Add page footers with page numbers across all pages
    final totalPages = document.pages.count;
    for (int pIdx = 0; pIdx < totalPages; pIdx++) {
      final pg = document.pages[pIdx];
      final pw = pg.getClientSize().width;
      final ph = pg.getClientSize().height;
      pg.graphics.drawLine(
        PdfPen(PdfColor(226, 232, 240), width: 0.6),
        Offset(0, ph - 20),
        Offset(pw, ph - 20),
      );
      pg.graphics.drawString(
        title,
        metaFont,
        brush: PdfSolidBrush(PdfColor(100, 116, 139)),
        bounds: Rect.fromLTWH(0, ph - 15, pw * 0.65, 14),
      );
      pg.graphics.drawString(
        'Page ${pIdx + 1} of $totalPages',
        metaFont,
        brush: PdfSolidBrush(PdfColor(100, 116, 139)),
        bounds: Rect.fromLTWH(pw * 0.65, ph - 15, pw * 0.35, 14),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
    }

    final bytes = await document.save();
    document.dispose();
    await outFile.writeAsBytes(bytes);

    return DocumentToolResult(
      status: 'success',
      outputPath: outputPath,
      pageCount: totalPages,
      text:
          'Attractive styled PDF document created at $outputPath ($totalPages page(s)).',
    ).toJsonString();
  }

  // ---------------------------------------------------------------------------
  // 2. Native Word (.docx) Generation (OpenXML ZIP Archive)
  // ---------------------------------------------------------------------------

  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static void _addUtf8ArchiveFile(Archive archive, String name, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static Future<String> _handleCreateDocx(Map<String, dynamic> args) async {
    final title = (args['title'] ?? 'Document').toString();
    final subtitle = (args['subtitle'] ?? '').toString();
    final content = (args['content'] ?? args['text'] ?? '').toString();
    final safeSlug = title
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final defaultName =
        '${safeSlug.isEmpty ? 'document' : safeSlug}_${DateTime.now().millisecondsSinceEpoch}.docx';
    final outputPath = await _resolveWritablePath(
      (args['output_path'] ?? args['path'] ?? defaultName).toString(),
      defaultFilename: defaultName,
    );

    final archive = Archive();

    _addUtf8ArchiveFile(archive, '[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''');

    _addUtf8ArchiveFile(archive, '_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''');

    _addUtf8ArchiveFile(archive, 'word/_rels/document.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');

    _addUtf8ArchiveFile(archive, 'word/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:sz w:val="22"/>
      <w:color w:val="1E293B"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:pPr><w:spacing w:before="120" w:after="160"/></w:pPr>
    <w:rPr>
      <w:b/>
      <w:sz w:val="44"/>
      <w:color w:val="0F2A4A"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:pPr><w:spacing w:before="240" w:after="100"/></w:pPr>
    <w:rPr>
      <w:b/>
      <w:sz w:val="32"/>
      <w:color w:val="0F2A4A"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:pPr><w:spacing w:before="180" w:after="80"/></w:pPr>
    <w:rPr>
      <w:b/>
      <w:sz w:val="26"/>
      <w:color w:val="0284C7"/>
    </w:rPr>
  </w:style>
</w:styles>''');

    final bodyBuf = StringBuffer();
    // Title paragraph
    bodyBuf.writeln('''
    <w:p>
      <w:pPr><w:pStyle w:val="Title"/></w:pPr>
      <w:r><w:t>${_xmlEscape(title)}</w:t></w:r>
    </w:p>''');
    if (subtitle.trim().isNotEmpty) {
      bodyBuf.writeln('''
    <w:p>
      <w:r>
        <w:rPr><w:i/><w:color w:val="64748B"/><w:sz w:val="22"/></w:rPr>
        <w:t>${_xmlEscape(subtitle)}</w:t>
      </w:r>
    </w:p>''');
    }

    final lines = content.split(RegExp(r'\r?\n'));
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        bodyBuf.writeln('<w:p/>');
        i++;
        continue;
      }

      // Markdown table
      if (line.startsWith('|') && line.endsWith('|')) {
        final tableRows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final tl = lines[i].trim();
          final inner = tl.substring(1, tl.length > 1 ? tl.length - 1 : 1);
          final cells = inner.split('|').map((c) => _stripInlineMd(c)).toList();
          if (!cells.every((c) => RegExp(r'^[:\-\s]*$').hasMatch(c))) {
            tableRows.add(cells);
          }
          i++;
        }
        if (tableRows.isNotEmpty) {
          bodyBuf.writeln('''
          <w:tbl>
            <w:tblPr>
              <w:tblBorders>
                <w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
                <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
                <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
                <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
              </w:tblBorders>
            </w:tblPr>''');
          for (int r = 0; r < tableRows.length; r++) {
            bodyBuf.writeln('<w:tr>');
            for (final cell in tableRows[r]) {
              final fill = r == 0 ? '0F2A4A' : (r.isEven ? 'F8FAFC' : 'FFFFFF');
              final textCol = r == 0 ? 'FFFFFF' : '1E293B';
              final boldTag = r == 0 ? '<w:b/>' : '';
              bodyBuf.writeln('''
              <w:tc>
                <w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$fill"/></w:tcPr>
                <w:p>
                  <w:r>
                    <w:rPr>$boldTag<w:color w:val="$textCol"/></w:rPr>
                    <w:t>${_xmlEscape(cell)}</w:t>
                  </w:r>
                </w:p>
              </w:tc>''');
            }
            bodyBuf.writeln('</w:tr>');
          }
          bodyBuf.writeln('</w:tbl>');
        }
        continue;
      }

      if (line.startsWith('# ')) {
        bodyBuf.writeln('''
        <w:p>
          <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
          <w:r><w:t>${_xmlEscape(_stripInlineMd(line.substring(2)))}</w:t></w:r>
        </w:p>''');
      } else if (line.startsWith('## ') || line.startsWith('### ')) {
        final clean = line.replaceFirst(RegExp(r'^#{2,3}\s+'), '');
        bodyBuf.writeln('''
        <w:p>
          <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
          <w:r><w:t>${_xmlEscape(_stripInlineMd(clean))}</w:t></w:r>
        </w:p>''');
      } else if (RegExp(r'^([-*•]|\d+\.)\s+').hasMatch(line)) {
        final clean = _stripInlineMd(
          line.replaceFirst(RegExp(r'^([-*•]|\d+\.)\s+'), ''),
        );
        bodyBuf.writeln('''
        <w:p>
          <w:pPr><w:ind w:left="360"/></w:pPr>
          <w:r><w:rPr><w:b/><w:color w:val="0284C7"/></w:rPr><w:t>• </w:t></w:r>
          <w:r><w:t>${_xmlEscape(clean)}</w:t></w:r>
        </w:p>''');
      } else {
        bodyBuf.writeln('''
        <w:p>
          <w:r><w:t>${_xmlEscape(_stripInlineMd(line))}</w:t></w:r>
        </w:p>''');
      }
      i++;
    }

    _addUtf8ArchiveFile(archive, 'word/document.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
${bodyBuf.toString()}
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''');

    final zipBytes = ZipEncoder().encode(archive);
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(zipBytes);

    return DocumentToolResult(
      status: 'success',
      outputPath: outputPath,
      text: 'Word (.docx) document successfully created at $outputPath.',
    ).toJsonString();
  }

  // ---------------------------------------------------------------------------
  // 3. Native Excel (.xlsx) Generation (OpenXML SpreadsheetML ZIP Archive)
  // ---------------------------------------------------------------------------

  static String _excelColumnName(int indexZeroBased) {
    var n = indexZeroBased + 1;
    var name = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  static List<({String name, List<List<dynamic>> rows})> _parseExcelSheets(
    Map<String, dynamic> args,
  ) {
    final result = <({String name, List<List<dynamic>> rows})>[];
    final defaultSheetName = (args['sheet_name'] ?? args['title'] ?? 'Sheet1')
        .toString();

    if (args['sheets'] is List) {
      int idx = 1;
      for (final s in args['sheets'] as List) {
        if (s is Map) {
          final name = (s['name'] ?? s['title'] ?? 'Sheet$idx').toString();
          final rawRows = s['rows'] as List? ?? const [];
          final rows = rawRows
              .map(
                (r) => r is List
                    ? r.map((c) => c).toList()
                    : <dynamic>[r.toString()],
              )
              .toList();
          result.add((name: name, rows: rows));
          idx++;
        }
      }
    }

    if (result.isEmpty && args['rows'] is List) {
      final rawRows = args['rows'] as List;
      final rows = <List<dynamic>>[];
      if (args['headers'] is List) {
        rows.add((args['headers'] as List).map((e) => e).toList());
      }
      for (final r in rawRows) {
        if (r is List) {
          rows.add(r.map((c) => c).toList());
        } else if (r is Map) {
          if (rows.isEmpty) {
            rows.add(r.keys.map((k) => k.toString()).toList());
          }
          rows.add(r.values.toList());
        }
      }
      result.add((name: defaultSheetName, rows: rows));
    }

    // Parse from markdown table or CSV content if provided in `content`
    if (result.isEmpty) {
      final content = (args['content'] ?? args['text'] ?? '').toString().trim();
      final rows = <List<dynamic>>[];
      if (content.isNotEmpty) {
        for (final rawLine in content.split(RegExp(r'\r?\n'))) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          if (line.startsWith('|') && line.endsWith('|')) {
            final inner = line.substring(1, line.length - 1);
            final cells = inner
                .split('|')
                .map((c) => _stripInlineMd(c))
                .toList();
            if (cells.every((c) => RegExp(r'^[:\-\s]*$').hasMatch(c))) {
              continue;
            }
            rows.add(cells);
          } else if (line.contains(',')) {
            rows.add(line.split(',').map((c) => c.trim()).toList());
          } else {
            rows.add([line]);
          }
        }
      }
      if (rows.isEmpty) {
        rows.add([args['title'] ?? 'Data']);
      }
      result.add((name: defaultSheetName, rows: rows));
    }

    return result;
  }

  static Future<String> _handleCreateXlsx(Map<String, dynamic> args) async {
    final title = (args['title'] ?? 'Spreadsheet').toString();
    final safeSlug = title
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final defaultName =
        '${safeSlug.isEmpty ? 'spreadsheet' : safeSlug}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final outputPath = await _resolveWritablePath(
      (args['output_path'] ?? args['path'] ?? defaultName).toString(),
      defaultFilename: defaultName,
    );

    final sheets = _parseExcelSheets(args);
    final archive = Archive();

    final sheetOverrides = StringBuffer();
    final workbookSheets = StringBuffer();
    final workbookRels = StringBuffer();

    for (int i = 0; i < sheets.length; i++) {
      final sNum = i + 1;
      final cleanName = _xmlEscape(
        sheets[i].name.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' '),
      );
      sheetOverrides.writeln(
        '  <Override PartName="/xl/worksheets/sheet$sNum.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
      workbookSheets.writeln(
        '    <sheet name="$cleanName" sheetId="$sNum" r:id="rId$sNum"/>',
      );
      workbookRels.writeln(
        '  <Relationship Id="rId$sNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$sNum.xml"/>',
      );
    }
    final stylesRelId = 'rId${sheets.length + 1}';
    workbookRels.writeln(
      '  <Relationship Id="$stylesRelId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );

    _addUtf8ArchiveFile(archive, '[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${sheetOverrides.toString()}</Types>''');

    _addUtf8ArchiveFile(archive, '_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');

    _addUtf8ArchiveFile(archive, 'xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
${workbookSheets.toString()}  </sheets>
</workbook>''');

    _addUtf8ArchiveFile(archive, 'xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${workbookRels.toString()}</Relationships>''');

    // Styles: style 0 = normal, style 1 = bold navy header
    _addUtf8ArchiveFile(archive, 'xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><color rgb="FF1E293B"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF0F2A4A"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
  </cellXfs>
</styleSheet>''');

    for (int i = 0; i < sheets.length; i++) {
      final sNum = i + 1;
      final rows = sheets[i].rows;
      final sheetData = StringBuffer();
      for (int r = 0; r < rows.length; r++) {
        final rowNum = r + 1;
        final cells = rows[r];
        sheetData.writeln('    <row r="$rowNum">');
        for (int c = 0; c < cells.length; c++) {
          final ref = '${_excelColumnName(c)}$rowNum';
          final styleAttr = r == 0 ? ' s="1"' : '';
          final rawVal = cells[c];
          final numVal = rawVal is num
              ? rawVal
              : num.tryParse(rawVal?.toString() ?? '');
          if (numVal != null && r > 0) {
            sheetData.writeln('      <c r="$ref"$styleAttr><v>$numVal</v></c>');
          } else {
            final strVal = _xmlEscape((rawVal ?? '').toString());
            sheetData.writeln(
              '      <c r="$ref"$styleAttr t="inlineStr"><is><t>$strVal</t></is></c>',
            );
          }
        }
        sheetData.writeln('    </row>');
      }

      _addUtf8ArchiveFile(archive, 'xl/worksheets/sheet$sNum.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
${sheetData.toString()}  </sheetData>
</worksheet>''');
    }

    final zipBytes = ZipEncoder().encode(archive);
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(zipBytes);

    return DocumentToolResult(
      status: 'success',
      outputPath: outputPath,
      text:
          'Excel (.xlsx) workbook successfully created at $outputPath with ${sheets.length} worksheet(s).',
    ).toJsonString();
  }

  // ---------------------------------------------------------------------------
  // 4. Native PowerPoint (.pptx) Generation (OpenXML PresentationML Archive)
  // ---------------------------------------------------------------------------

  static List<({String title, List<String> bullets})> _parsePptxSlides(
    Map<String, dynamic> args,
  ) {
    final slides = <({String title, List<String> bullets})>[];
    final deckTitle = (args['title'] ?? 'Presentation').toString();
    final deckSubtitle = (args['subtitle'] ?? '').toString();

    if (args['slides'] is List) {
      for (final s in args['slides'] as List) {
        if (s is Map) {
          final sTitle = (s['title'] ?? s['heading'] ?? 'Slide').toString();
          final rawBullets = s['bullets'] ?? s['points'] ?? s['content'];
          final bullets = <String>[];
          if (rawBullets is List) {
            bullets.addAll(rawBullets.map((b) => _stripInlineMd(b.toString())));
          } else if (rawBullets is String) {
            for (final line in rawBullets.split(RegExp(r'\r?\n'))) {
              final clean = _stripInlineMd(
                line.trim().replaceFirst(RegExp(r'^([-*•]|\d+\.)\s+'), ''),
              );
              if (clean.isNotEmpty) bullets.add(clean);
            }
          }
          slides.add((title: sTitle, bullets: bullets));
        }
      }
    }

    if (slides.isEmpty) {
      // Parse markdown into slides split by `---`, `# `, or `## `
      final content = (args['content'] ?? args['text'] ?? '').toString().trim();
      if (content.isNotEmpty) {
        String currentSlideTitle = deckTitle;
        List<String> currentBullets = <String>[];
        if (deckSubtitle.isNotEmpty) {
          currentBullets.add(deckSubtitle);
        }

        for (final rawLine in content.split(RegExp(r'\r?\n'))) {
          final line = rawLine.trim();
          if (line.isEmpty || RegExp(r'^-{3,}$').hasMatch(line)) continue;
          if (line.startsWith('# ') || line.startsWith('## ')) {
            if (currentBullets.isNotEmpty) {
              slides.add((title: currentSlideTitle, bullets: currentBullets));
            }
            currentSlideTitle = _stripInlineMd(
              line.replaceFirst(RegExp(r'^#{1,2}\s+'), ''),
            );
            currentBullets = <String>[];
          } else {
            final clean = _stripInlineMd(
              line.replaceFirst(RegExp(r'^([-*•]|\d+\.)\s+'), ''),
            );
            if (clean.isNotEmpty) {
              currentBullets.add(clean);
            }
          }
        }
        if (currentBullets.isNotEmpty || slides.isEmpty) {
          slides.add((title: currentSlideTitle, bullets: currentBullets));
        }
      } else {
        slides.add((
          title: deckTitle,
          bullets: deckSubtitle.isNotEmpty ? [deckSubtitle] : ['Overview'],
        ));
      }
    }

    return slides;
  }

  static Future<String> _handleCreatePptx(Map<String, dynamic> args) async {
    final title = (args['title'] ?? 'Presentation').toString();
    final safeSlug = title
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final defaultName =
        '${safeSlug.isEmpty ? 'presentation' : safeSlug}_${DateTime.now().millisecondsSinceEpoch}.pptx';
    final outputPath = await _resolveWritablePath(
      (args['output_path'] ?? args['path'] ?? defaultName).toString(),
      defaultFilename: defaultName,
    );

    final slides = _parsePptxSlides(args);
    final archive = Archive();

    final slideOverrides = StringBuffer();
    final sldIdLst = StringBuffer();
    final presRels = StringBuffer();

    for (int i = 0; i < slides.length; i++) {
      final sNum = i + 1;
      final sldId = 256 + i;
      slideOverrides.writeln(
        '  <Override PartName="/ppt/slides/slide$sNum.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
      sldIdLst.writeln('    <p:sldId id="$sldId" r:id="rId$sNum"/>');
      presRels.writeln(
        '  <Relationship Id="rId$sNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$sNum.xml"/>',
      );
    }

    _addUtf8ArchiveFile(archive, '[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
${slideOverrides.toString()}</Types>''');

    _addUtf8ArchiveFile(archive, '_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''');

    _addUtf8ArchiveFile(archive, 'ppt/presentation.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>
${sldIdLst.toString()}  </p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>''');

    _addUtf8ArchiveFile(archive, 'ppt/_rels/presentation.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${presRels.toString()}</Relationships>''');

    for (int i = 0; i < slides.length; i++) {
      final sNum = i + 1;
      final slide = slides[i];
      final bulletsXml = StringBuffer();
      if (slide.bullets.isEmpty) {
        bulletsXml.writeln('<a:p><a:r><a:t></a:t></a:r></a:p>');
      } else {
        for (final b in slide.bullets) {
          bulletsXml.writeln('''
            <a:p>
              <a:pPr marL="342900" indent="-171450"/>
              <a:r>
                <a:rPr lang="en-US" sz="2000" b="1"><a:solidFill><a:srgbClr val="0284C7"/></a:solidFill></a:rPr>
                <a:t>•  </a:t>
              </a:r>
              <a:r>
                <a:rPr lang="en-US" sz="2000"><a:solidFill><a:srgbClr val="1E293B"/></a:solidFill></a:rPr>
                <a:t>${_xmlEscape(b)}</a:t>
              </a:r>
            </a:p>''');
        }
      }

      _addUtf8ArchiveFile(archive, 'ppt/slides/slide$sNum.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Title 1"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="685800" y="457200"/>
            <a:ext cx="10820400" cy="1143000"/>
          </a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p>
            <a:r>
              <a:rPr lang="en-US" sz="3200" b="1">
                <a:solidFill><a:srgbClr val="0F2A4A"/></a:solidFill>
              </a:rPr>
              <a:t>${_xmlEscape(slide.title)}</a:t>
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="3" name="Content 2"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="685800" y="1828800"/>
            <a:ext cx="10820400" cy="4343400"/>
          </a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
${bulletsXml.toString()}        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''');
    }

    final zipBytes = ZipEncoder().encode(archive);
    final outFile = File(outputPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(zipBytes);

    return DocumentToolResult(
      status: 'success',
      outputPath: outputPath,
      pageCount: slides.length,
      text:
          'PowerPoint (.pptx) presentation successfully created at $outputPath with ${slides.length} slide(s).',
    ).toJsonString();
  }

  // ---------------------------------------------------------------------------
  // 5. Merge PDFs
  // ---------------------------------------------------------------------------

  static Future<String> _handleMergePdfs(Map<String, dynamic> args) async {
    final paths =
        (args['file_paths'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    final defaultName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
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

    for (final pStr in paths) {
      final f = File(pStr);
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
  }
}
