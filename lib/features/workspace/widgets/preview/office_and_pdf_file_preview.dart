import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:Kelivo/core/services/chat/document_text_extractor.dart';
import 'package:Kelivo/features/workspace/workspace_layout.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/markdown/markdown_with_code_highlight.dart';
import 'package:Kelivo/shared/utils/format_bytes.dart';
import 'package:Kelivo/shared/widgets/app_selection_area.dart';
import 'package:Kelivo/shared/widgets/ios_tile_button.dart';
import 'package:Kelivo/shared/widgets/segmented_tabs.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

import 'preview_actions.dart';
import 'preview_file_type.dart';
import 'preview_states.dart';

/// In-app PDF preview widget used inside [FilePreviewFrame] and [SidePanelFilePreview].
class PdfFilePreview extends StatefulWidget {
  const PdfFilePreview({super.key, required this.file});

  final File file;

  @override
  State<PdfFilePreview> createState() => _PdfFilePreviewState();
}

class _PdfFilePreviewState extends State<PdfFilePreview> {
  late final PdfViewerController _controller;
  int _pageNumber = 1;
  int _pageCount = 0;
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _loadPdf();
  }

  @override
  void didUpdateWidget(covariant PdfFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _loadPdf();
    }
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await widget.file.exists()) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'PDF file not found on disk';
          });
        }
        return;
      }
      final b = await widget.file.readAsBytes();
      if (b.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'PDF file is empty (0 bytes)';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _bytes = b;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to read PDF: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PreviewLoading();
    }
    if (_error != null || _bytes == null) {
      return PreviewError(onRetry: _loadPdf, message: _error);
    }

    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border(
              bottom: BorderSide(
                color: cs.onSurface.withValues(alpha: 0.08),
                width: 0.6,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Lucide.FileText, size: 15, color: Color(0xFFD14D41)),
              const SizedBox(width: 8),
              Text(
                _pageCount > 0
                    ? 'Page $_pageNumber of $_pageCount'
                    : 'PDF Document',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Lucide.ZoomOut, size: 16),
                tooltip: 'Zoom Out',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _controller.zoomLevel = (_controller.zoomLevel - 0.25).clamp(
                    1.0,
                    3.0,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Lucide.ZoomIn, size: 16),
                tooltip: 'Zoom In',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _controller.zoomLevel = (_controller.zoomLevel + 0.25).clamp(
                    1.0,
                    3.0,
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SfPdfViewer.memory(
            _bytes!,
            controller: _controller,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            pageSpacing: 8,
            onDocumentLoaded: (details) {
              if (mounted) {
                setState(() {
                  _pageCount = details.document.pages.count;
                  _pageNumber = _controller.pageNumber.clamp(1, _pageCount);
                });
              }
            },
            onDocumentLoadFailed: (details) {
              if (mounted) {
                setState(() {
                  _error = details.description.isNotEmpty
                      ? details.description
                      : details.error;
                });
              }
            },
            onPageChanged: (details) {
              if (mounted) {
                setState(() {
                  _pageNumber = details.newPageNumber;
                });
              }
            },
          ),
        ),
      ],
    );
  }
}

/// In-app preview widget for Office documents (.docx, .pptx, .xlsx).
/// Extracts rich structured text/tables/slides so the user can view them
/// directly in the app without needing external Office software.
class OfficeFilePreview extends StatefulWidget {
  const OfficeFilePreview({
    super.key,
    required this.file,
    this.autoLoad = true,
  });

  final File file;
  final bool autoLoad;

  @override
  State<OfficeFilePreview> createState() => _OfficeFilePreviewState();
}

class _OfficeFilePreviewState extends State<OfficeFilePreview> {
  String? _extractedMarkdown;
  bool _loading = true;
  Object? _error;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant OfficeFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _extractedMarkdown = null;
      _error = null;
      _showRaw = false;
      if (widget.autoLoad) unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ext = p.extension(widget.file.path).toLowerCase();
      final mime = switch (ext) {
        '.docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.pptx' =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        '.xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        _ => 'application/octet-stream',
      };
      final text = await DocumentTextExtractor.extractResolved(
        path: widget.file.path,
        mime: mime,
      );
      if (!mounted) return;
      setState(() {
        _extractedMarkdown = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PreviewLoading();
    }
    if (_error != null) {
      return PreviewError(onRetry: _load);
    }

    final content = _extractedMarkdown ?? '';
    final cs = Theme.of(context).colorScheme;
    final desktop = useDesktopWorkspaceLayout(context);
    final style = previewFileTypeStyle(widget.file.path);
    final ext = p
        .extension(widget.file.path)
        .replaceFirst('.', '')
        .toUpperCase();
    final sizeBytes = widget.file.existsSync() ? widget.file.lengthSync() : 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 15, color: style.color),
                    const SizedBox(width: 6),
                    Text(
                      '$ext · ${formatBytes(sizeBytes)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppFontWeights.semibold,
                        color: style.color,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IosTileButton(
                icon: Lucide.ExternalLink,
                label: 'Open Externally',
                onTap: () =>
                    unawaited(openPreviewFileExternally(context, widget.file)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SegmentedTabs(
            tabs: const [
              SegmentedTab(label: 'Document Preview', icon: Lucide.Eye),
              SegmentedTab(label: 'Plain Text', icon: Lucide.FileText),
            ],
            index: _showRaw ? 1 : 0,
            onChanged: (next) => setState(() => _showRaw = next == 1),
          ),
        ),
        Expanded(
          child: content.trim().isEmpty
              ? Center(
                  child: Text(
                    'No readable text content found in $ext file.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : _showRaw
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: AppSelectionArea(
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: desktop ? 12.5 : 13.5,
                        height: 1.5,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: desktop ? 780 : double.infinity,
                      ),
                      child: AppSelectionArea(
                        child: MarkdownWithCodeHighlight(
                          text: content,
                          useBlockRendering: true,
                          baseStyle: TextStyle(
                            fontSize: desktop ? 14.0 : 15.2,
                            height: 1.55,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
