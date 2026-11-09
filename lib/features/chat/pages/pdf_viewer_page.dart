import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

/// Fullscreen interactive PDF viewer matching reference design,
/// complete with top close button, zoom/pan navigation, and bottom
/// Download & Share actions.
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key, required this.filePath, this.title});

  final String filePath;
  final String? title;

  static Route<void> route({required String filePath, String? title}) {
    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) =>
          PdfViewerPage(filePath: filePath, title: title),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final PdfViewerController _pdfViewerController;
  bool _isSaving = false;
  int _pageNumber = 1;
  int _pageCount = 0;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _loadError;

  String get _displayTitle => widget.title ?? p.basename(widget.filePath);

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = 'PDF file not found on device';
          });
        }
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = 'PDF file is empty (0 bytes)';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Failed to read PDF: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _handleDownload() async {
    if (_isSaving) return;
    Haptics.light();
    final source = File(widget.filePath);
    if (!await source.exists()) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'PDF file not found on device',
          type: NotificationType.error,
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    final basename = p.basename(widget.filePath);

    try {
      String? targetDir;
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          targetDir = publicDownload.path;
        }
      }

      if (targetDir == null) {
        final d =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        targetDir = d.path;
      }

      final targetPath = p.join(targetDir, basename);
      await source.copy(targetPath);

      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Saved to Downloads: $basename',
          type: NotificationType.success,
          actionLabel: 'Open',
          onAction: () => OpenFilex.open(targetPath),
        );
      }
    } catch (e) {
      // Fallback: share
      try {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(source.path)], subject: basename),
        );
      } catch (_) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: 'Failed to save download: $e',
            type: NotificationType.error,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleShare() async {
    Haptics.light();
    final file = File(widget.filePath);
    if (!await file.exists()) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'PDF file not available to share',
          type: NotificationType.error,
        );
      }
      return;
    }

    try {
      final basename = p.basename(widget.filePath);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: basename),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Failed to share: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    final fileExists = file.existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1216),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Close "X" button
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Lucide.X, color: Colors.white, size: 24),
                    splashRadius: 22,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                    ),
                  ),
                  if (_pageCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_pageNumber / $_pageCount',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(
                      Lucide.ZoomOut,
                      color: Colors.white70,
                      size: 19,
                    ),
                    tooltip: 'Zoom Out',
                    splashRadius: 20,
                    onPressed: () {
                      _pdfViewerController.zoomLevel =
                          (_pdfViewerController.zoomLevel - 0.25).clamp(
                            1.0,
                            3.0,
                          );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Lucide.ZoomIn,
                      color: Colors.white70,
                      size: 19,
                    ),
                    tooltip: 'Zoom In',
                    splashRadius: 20,
                    onPressed: () {
                      _pdfViewerController.zoomLevel =
                          (_pdfViewerController.zoomLevel + 0.25).clamp(
                            1.0,
                            3.0,
                          );
                    },
                  ),
                ],
              ),
            ),

            // Main PDF Viewer Area
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    )
                  : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Lucide.CircleAlert,
                              size: 44,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _loadPdf,
                                  icon: const Icon(Lucide.RotateCw, size: 16),
                                  label: const Text('Retry'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      OpenFilex.open(widget.filePath),
                                  icon: const Icon(
                                    Lucide.ExternalLink,
                                    size: 16,
                                  ),
                                  label: const Text('Open in App'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.15),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : SfPdfViewer.memory(
                      _pdfBytes!,
                      controller: _pdfViewerController,
                      canShowScrollHead: true,
                      canShowScrollStatus: true,
                      pageSpacing: 8,
                      onDocumentLoaded: (details) {
                        if (mounted) {
                          setState(() {
                            _pageCount = details.document.pages.count;
                            _pageNumber = _pdfViewerController.pageNumber.clamp(
                              1,
                              _pageCount,
                            );
                          });
                        }
                      },
                      onDocumentLoadFailed: (details) {
                        if (mounted) {
                          setState(() {
                            _loadError = details.description.isNotEmpty
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

            // Bottom Bar with Download, Share, and Open Externally buttons
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF161A22),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Download Button
                  _buildBottomActionButton(
                    icon: Lucide.Download,
                    label: 'Download',
                    onTap: _handleDownload,
                  ),

                  // Share Button
                  _buildBottomActionButton(
                    icon: Lucide.Share2,
                    label: 'Share',
                    onTap: _handleShare,
                  ),

                  // Open Externally Button
                  _buildBottomActionButton(
                    icon: Lucide.ExternalLink,
                    label: 'Open App',
                    onTap: () => OpenFilex.open(widget.filePath),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: AppFontWeights.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
