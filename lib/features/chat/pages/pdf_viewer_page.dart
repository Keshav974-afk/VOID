import 'dart:io';

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
  const PdfViewerPage({
    super.key,
    required this.filePath,
    this.title,
  });

  final String filePath;
  final String? title;

  static Route<void> route({
    required String filePath,
    String? title,
  }) {
    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => PdfViewerPage(
        filePath: filePath,
        title: title,
      ),
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

  String get _displayTitle =>
      widget.title ?? p.basename(widget.filePath);

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
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
        final d = await getDownloadsDirectory() ??
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
                    icon: const Icon(
                      Lucide.X,
                      color: Colors.white,
                      size: 24,
                    ),
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
                ],
              ),
            ),

            // Main PDF Viewer Area
            Expanded(
              child: fileExists
                  ? SfPdfViewer.file(
                      file,
                      controller: _pdfViewerController,
                      canShowScrollHead: false,
                      canShowScrollStatus: true,
                      pageSpacing: 8,
                    )
                  : const Center(
                      child: Text(
                        'PDF file could not be loaded',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
            ),

            // Bottom Bar with Download and Share buttons
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                mainAxisAlignment: MainAxisAlignment.spaceAround,
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
