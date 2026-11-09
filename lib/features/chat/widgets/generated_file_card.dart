import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/models/vps_config.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/sandbox_vps/sandbox_vps_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../workspace/widgets/preview/file_preview.dart';
import '../pages/image_viewer_page.dart';
import '../pages/pdf_viewer_page.dart';

/// Extracts explicitly presented file deliverables (PDF, documents, code, archives, artifacts)
/// from markdown or tool text. If an image is already rendered in markdown, it is not duplicated.
List<String> extractGeneratedFilePaths(String text) {
  if (text.isEmpty) return const [];
  final paths = <String>{};

  // Find all images already rendered in Markdown e.g. ![...](image.png)
  final mdImages = <String>{};
  final mdImgRegex = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
  for (final m in mdImgRegex.allMatches(text)) {
    var src = (m.group(1) ?? '').trim();
    src = src.replaceAll(RegExp(r'''[',`"\):;\.]+$'''), '');
    mdImages.add(src.toLowerCase());
    mdImages.add(p.basename(src).toLowerCase());
  }

  const allowedExts = {
    '.pdf', '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.csv', '.tsv',
    '.apk', '.exe', '.zip', '.tar', '.gz', '.7z',
    '.py', '.js', '.ts', '.dart', '.json', '.html', '.css', '.sh', '.sql',
    '.txt', '.md', '.java', '.cpp', '.c', '.rs',
    '.png', '.jpg', '.jpeg', '.webp', '.gif',
  };

  bool isAlreadyRenderedImage(String path) {
    final lower = path.toLowerCase();
    final isImage = lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
    if (!isImage) return false;
    final base = p.basename(lower);
    return mdImages.contains(lower) || mdImages.contains(base);
  }

  // 1. Markdown file links: [label](path) (excluding images ![...](...))
  final mdLinkRegex = RegExp(r'(?<!!|)\[([^\]]+)\]\(([^)]+)\)');
  for (final m in mdLinkRegex.allMatches(text)) {
    var target = (m.group(2) ?? '').trim();
    target = target.replaceAll(RegExp(r'''[',`"\):;\.]+$'''), '');
    final ext = p.extension(target).toLowerCase();
    if (allowedExts.contains(ext)) {
      if (!isAlreadyRenderedImage(target)) {
        paths.add(target);
      }
    }
  }

  // 2. Deliverable declaration lines
  final deliverableLineRegex = RegExp(
    r'''(?:^|\n)\s*(?:Download|Deliverable|Generated(?:\s+file)?|File(?:\s+saved)?|Saved to|Artifact|Output)\s*:\s*([^\s\n"'`<>\[\]\(\)\*]+)''',
    caseSensitive: false,
  );
  for (final m in deliverableLineRegex.allMatches(text)) {
    var pStr = (m.group(1) ?? '').trim();
    pStr = pStr.replaceAll(RegExp(r'''[',`"\):;\.]+$'''), '');
    final ext = p.extension(pStr).toLowerCase();
    if (allowedExts.contains(ext)) {
      if (!isAlreadyRenderedImage(pStr)) {
        paths.add(pStr);
      }
    }
  }

  return paths.toList();
}

/// Card that renders generated documents (PDF, etc.) or images directly in chat,
/// matching reference UI with live preview, full-screen viewer, and actions.
class GeneratedFileCard extends StatefulWidget {
  const GeneratedFileCard({
    super.key,
    required this.filePath,
    this.pageCount,
    this.status,
    this.text,
    this.isImage = false,
    this.title,
  });

  final String filePath;
  final int? pageCount;
  final String? status;
  final String? text;
  final bool isImage;
  final String? title;

  @override
  State<GeneratedFileCard> createState() => _GeneratedFileCardState();
}

class _GeneratedFileCardState extends State<GeneratedFileCard> {
  String? _localPath;
  bool _isFetching = false;
  String? _fetchError;
  int? _fileSize;
  int? _resolvedPageCount;
  Completer<String?>? _activeDownload;

  bool get _isPdf =>
      p.extension(widget.filePath).toLowerCase() == '.pdf' ||
      (_resolvedPageCount != null);

  bool get _isImg =>
      widget.isImage ||
      const [
        '.png',
        '.jpg',
        '.jpeg',
        '.webp',
        '.gif',
      ].contains(p.extension(widget.filePath).toLowerCase());

  @override
  void initState() {
    super.initState();
    _resolvedPageCount = widget.pageCount;
    _resolveFile();
  }

  @override
  void didUpdateWidget(covariant GeneratedFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _resolvedPageCount = widget.pageCount;
      _resolveFile();
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  int? _estimatePdfPages(File file) {
    try {
      final bytes = file.readAsBytesSync();
      final str = String.fromCharCodes(bytes);
      final count = RegExp(r'/Type\s*/Page[^s]').allMatches(str).length;
      return count > 0 ? count : null;
    } catch (_) {
      return null;
    }
  }

  Future<VpsConfig> _loadVpsConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vps_config_v1');
      if (raw != null && raw.trim().isNotEmpty) {
        return VpsConfig.fromJsonString(raw);
      }
    } catch (_) {}
    return const VpsConfig();
  }

  Future<void> _resolveFile({bool forceRemote = false}) async {
    final fixedPath = SandboxPathResolver.fix(widget.filePath);
    if (fixedPath.startsWith('http://') ||
        fixedPath.startsWith('https://') ||
        fixedPath.startsWith('data:')) {
      if (mounted) {
        setState(() {
          _localPath = fixedPath;
          _isFetching = false;
          _fetchError = null;
        });
      }
      return;
    }

    // 1. Direct local file check
    final direct = File(fixedPath);
    if (!forceRemote && await direct.exists()) {
      final len = await direct.length();
      if (mounted) {
        setState(() {
          _localPath = direct.path;
          _fileSize = len;
          _isFetching = false;
          _fetchError = null;
          if (_isPdf && _resolvedPageCount == null) {
            _resolvedPageCount = _estimatePdfPages(direct);
          }
        });
      }
      return;
    }

    // 2. Check cached file in application documents directory
    final basename = p.basename(fixedPath);
    final docsDir = await getApplicationDocumentsDirectory();
    final cached = File(p.join(docsDir.path, basename));
    if (!forceRemote && await cached.exists()) {
      final len = await cached.length();
      if (len > 0) {
        if (mounted) {
          setState(() {
            _localPath = cached.path;
            _fileSize = len;
            _isFetching = false;
            _fetchError = null;
            if (_isPdf && _resolvedPageCount == null) {
              _resolvedPageCount = _estimatePdfPages(cached);
            }
          });
        }
        return;
      }
    }

    // 3. Remote VPS path detection
    final isRemote =
        fixedPath.startsWith('/tmp/') ||
        fixedPath.startsWith('/root/') ||
        fixedPath.startsWith('/var/') ||
        fixedPath.startsWith('/home/') ||
        !fixedPath.contains(Platform.isWindows ? r'\' : '/');

    if (isRemote || !await direct.exists()) {
      if (mounted) {
        setState(() {
          _isFetching = true;
          _fetchError = null;
        });
      }

      final completer = Completer<String?>();
      _activeDownload = completer;

      try {
        final vpsCfg = await _loadVpsConfig();
        final downloaded = await SandboxVpsService.instance.downloadBinaryFile(
          config: vpsCfg,
          remotePath: widget.filePath,
          localPath: cached.path,
        );
        final len = await downloaded.length();
        if (mounted) {
          setState(() {
            _localPath = downloaded.path;
            _fileSize = len;
            _isFetching = false;
            _fetchError = null;
            if (_isPdf && _resolvedPageCount == null) {
              _resolvedPageCount = _estimatePdfPages(downloaded);
            }
          });
        }
        completer.complete(downloaded.path);
      } catch (e) {
        if (mounted) {
          setState(() {
            _isFetching = false;
            _fetchError = e.toString();
          });
        }
        completer.complete(null);
      } finally {
        if (_activeDownload == completer) {
          _activeDownload = null;
        }
      }
    }
  }

  Future<void> _handleDownload(BuildContext context) async {
    Haptics.light();
    String? path = _localPath;

    if (_isFetching && _activeDownload != null) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Downloading file from Sandbox VPS, please wait...',
          type: NotificationType.info,
        );
      }
      path = await _activeDownload!.future;
    } else if (path == null) {
      await _resolveFile(forceRemote: true);
      path = _localPath;
    }

    if (path == null || !await File(path).exists()) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: _fetchError != null
              ? 'Failed to fetch file: $_fetchError'
              : 'File not found on device: ${widget.filePath}',
          type: NotificationType.error,
        );
      }
      return;
    }

    final source = File(path);
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

      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Saved to Downloads: $basename',
          type: NotificationType.success,
          actionLabel: 'Open',
          onAction: () => _handleOpen(context),
        );
      }
    } catch (e) {
      try {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], subject: basename),
        );
      } catch (_) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            message: 'Failed to save download: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _handleOpen(BuildContext context) async {
    Haptics.light();
    String? path = _localPath;

    if (_isFetching && _activeDownload != null) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Downloading file, please wait...',
          type: NotificationType.info,
        );
      }
      path = await _activeDownload!.future;
    } else if (path == null) {
      await _resolveFile(forceRemote: true);
      path = _localPath;
    }

    if (path == null || !await File(path).exists()) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: _fetchError != null
              ? 'Failed to fetch: $_fetchError'
              : 'File not found: ${widget.filePath}',
          type: NotificationType.error,
        );
      }
      return;
    }

    if (!context.mounted) return;
    final validPath = path;

    if (_isPdf) {
      Navigator.of(context).push(
        PdfViewerPage.route(
          filePath: validPath,
          title: widget.title ?? p.basename(widget.filePath),
        ),
      );
      return;
    }

    if (_isImg) {
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, __, ___) =>
              ImageViewerPage(images: [validPath], initialIndex: 0),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
        ),
      );
      return;
    }

    try {
      await showFilePreview(
        context,
        File(validPath),
        title: widget.title ?? p.basename(widget.filePath),
      );
    } catch (e) {
      try {
        final res = await OpenFilex.open(validPath);
        if (res.type != ResultType.done && context.mounted) {
          showAppSnackBar(
            context,
            message: 'Could not open file: ${res.message}',
            type: NotificationType.warning,
          );
        }
      } catch (_) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            message: 'Error opening file: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    Haptics.light();
    String? path = _localPath;

    if (_isFetching && _activeDownload != null) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Downloading file, please wait...',
          type: NotificationType.info,
        );
      }
      path = await _activeDownload!.future;
    } else if (path == null) {
      await _resolveFile(forceRemote: true);
      path = _localPath;
    }

    if (path == null || !await File(path).exists()) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'File not available to share: ${widget.filePath}',
          type: NotificationType.error,
        );
      }
      return;
    }

    try {
      final basename = p.basename(widget.filePath);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: basename),
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Failed to share: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _handleCopyPath(BuildContext context) async {
    Haptics.light();
    final toCopy = _localPath ?? widget.filePath;
    await Clipboard.setData(ClipboardData(text: toCopy));
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: 'Copied file path to clipboard',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final exists = _localPath != null && File(_localPath!).existsSync();
    if (!exists && !_isFetching && _fetchError != null) {
      return const SizedBox.shrink();
    }
    final basename = widget.title ?? p.basename(widget.filePath);

    final cardBg = isDark ? const Color(0xFF161A22) : const Color(0xFFF1F5F9);
    final borderCol = isDark
        ? const Color(0xFF262D38)
        : const Color(0xFFCBD5E1);

    // 1. Specialized PDF Card (matching reference screenshot Image 1)
    if (_isPdf) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderCol, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top download progress bar
            if (_isFetching)
              const LinearProgressIndicator(
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
              ),

            // Card Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  // Red PDF icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Lucide.FileText,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Title
                  Expanded(
                    child: Text(
                      basename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.emphasis,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  // Copy link icon
                  IconButton(
                    icon: Icon(
                      Lucide.Link2,
                      size: 19,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    splashRadius: 18,
                    tooltip: 'Copy path',
                    onPressed: () => _handleCopyPath(context),
                  ),
                  // Fullscreen expand icon
                  IconButton(
                    icon: Icon(
                      Lucide.Maximize2,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    splashRadius: 18,
                    tooltip: 'Fullscreen',
                    onPressed: () => _handleOpen(context),
                  ),
                ],
              ),
            ),

            // Card Body: Live Preview or Fetching State
            if (exists) ...[
              GestureDetector(
                onTap: () => _handleOpen(context),
                child: Container(
                  height: 380,
                  width: double.infinity,
                  color: Colors.white,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: AbsorbPointer(
                          child: SfPdfViewer.file(
                            File(_localPath!),
                            canShowScrollHead: false,
                            canShowScrollStatus: false,
                            canShowPaginationDialog: false,
                            enableDoubleTapZooming: false,
                            pageSpacing: 0,
                          ),
                        ),
                      ),
                      // Floating "PDF" badge at bottom center (Image 1 reference)
                      Positioned(
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text(
                            'PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                height: 140,
                alignment: Alignment.center,
                child: _isFetching
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFEF4444),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Loading PDF preview...',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _fetchError != null
                                ? 'Failed to fetch: $_fetchError'
                                : 'Tap to load PDF',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _handleOpen(context),
                            icon: const Icon(Lucide.Eye, size: 14),
                            label: const Text('Open'),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      );
    }

    // 2. Standard Card for Images and other Documents
    final sizeStr = _fileSize != null ? _formatFileSize(_fileSize!) : '';
    final ext = p.extension(widget.filePath).replaceAll('.', '').toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top download progress bar
          if (_isFetching)
            const LinearProgressIndicator(
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1D9BF0)),
            ),

          // Image Preview
          if (_isImg && exists) ...[
            GestureDetector(
              onTap: () => _handleOpen(context),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 240),
                width: double.infinity,
                color: isDark ? Colors.black26 : Colors.black12,
                child: Image.file(
                  File(_localPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],

          // File Info Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isImg
                        ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                        : const Color(0xFF64748B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: _isFetching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF38BDF8),
                            ),
                          ),
                        )
                      : Icon(
                          _isImg ? Lucide.Image : Lucide.File,
                          size: 22,
                          color: _isImg
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF94A3B8),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        basename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.emphasis,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (_isFetching) ...[
                        Text(
                          'Downloading file...',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF0284C7),
                          ),
                        ),
                      ] else if (_fetchError != null) ...[
                        Row(
                          children: [
                            Text(
                              'Download failed',
                              style: TextStyle(fontSize: 12, color: cs.error),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _resolveFile(forceRemote: true),
                              child: Text(
                                'Retry',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFF0284C7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.black.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ext.isNotEmpty ? ext : 'FILE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            ),
                            if (sizeStr.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '• $sizeStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildActionButton(
                  context,
                  icon: Lucide.Eye,
                  label: 'Open',
                  isPrimary: true,
                  onTap: () => _handleOpen(context),
                ),
                _buildActionButton(
                  context,
                  icon: Lucide.Download,
                  label: 'Download',
                  onTap: () => _handleDownload(context),
                ),
                _buildActionButton(
                  context,
                  icon: Lucide.Share2,
                  label: 'Share',
                  onTap: () => _handleShare(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isPrimary
        ? (isDark ? const Color(0xFF1D9BF0) : const Color(0xFF0284C7))
        : (isDark ? const Color(0xFF232A34) : const Color(0xFFE2E8F0));
    final fg = isPrimary
        ? Colors.white
        : (isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.medium,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
