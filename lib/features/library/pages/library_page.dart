import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/app_directories.dart';
import '../../chat/pages/image_viewer_page.dart';
import '../../chat/pages/pdf_viewer_page.dart';
import '../../workspace/widgets/preview/file_preview.dart';
import '../../workspace/widgets/preview/preview_file_type.dart';

enum LibraryFilterTab { all, media, apps, files }

class LibraryItem {
  final File file;
  final String name;
  final int size;
  final DateTime modified;
  final bool isImage;
  final bool isMedia;
  final bool isApp;

  LibraryItem({
    required this.file,
    required this.name,
    required this.size,
    required this.modified,
    required this.isImage,
    required this.isMedia,
    required this.isApp,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} kB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    return DateFormat('d MMM').format(modified);
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryFilterTab _currentTab = LibraryFilterTab.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<LibraryItem> _items = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadRealFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static bool _isCodeOrInternalArtifact(String fullPath, String basename) {
    if (basename.startsWith('.')) return true;
    final normalized = fullPath.replaceAll(r'\', '/').toLowerCase();

    // Strictly exclude repository source directories, build artifacts & dependencies
    const blacklistedDirs = [
      '/.git/',
      '/.dart_tool/',
      '/.idea/',
      '/.vscode/',
      '/build/',
      '/node_modules/',
      '/dependencies/',
      '/android/',
      '/ios/',
      '/windows/',
      '/macos/',
      '/linux/',
      '/web/',
      '/lib/',
      '/test/',
      '/integration_test/',
      '/bin/',
      '/obj/',
    ];
    for (final dir in blacklistedDirs) {
      if (normalized.contains(dir)) return true;
    }

    // Exclude code files and project build definitions
    final lowerName = basename.toLowerCase();
    if (lowerName == 'pubspec.yaml' ||
        lowerName == 'pubspec.lock' ||
        lowerName == 'analysis_options.yaml' ||
        lowerName == 'cmakelists.txt' ||
        lowerName == 'makefile' ||
        lowerName == 'dockerfile' ||
        lowerName.endsWith('.g.dart') ||
        lowerName.endsWith('.freezed.dart') ||
        lowerName.endsWith('.dart')) {
      return true;
    }

    // Exclude internal database files, locks, and compiler logs
    final ext = basename.contains('.')
        ? basename.split('.').last.toLowerCase()
        : '';
    const internalExts = {
      'db',
      'db-shm',
      'db-wal',
      'sqlite',
      'sqlite3',
      'hive',
      'lock',
      'tmp',
      'log',
      'pdb',
      'obj',
      'o',
      'ilk',
      'class',
      'dex',
      'dylib',
      'so',
      'dll',
    };
    if (internalExts.contains(ext)) return true;

    return false;
  }

  Future<void> _loadRealFiles() async {
    setState(() => _isLoading = true);
    try {
      final Set<String> visitedPaths = {};
      final List<LibraryItem> loaded = [];

      final dirsToScan = <Directory>[];

      // 1. User uploaded files
      try {
        final uploadDir = await AppDirectories.getUploadDirectory();
        if (await uploadDir.exists()) dirsToScan.add(uploadDir);
      } catch (_) {}

      // 2. User images / generated pictures
      try {
        final imagesDir = await AppDirectories.getImagesDirectory();
        if (await imagesDir.exists()) dirsToScan.add(imagesDir);
      } catch (_) {}

      // 3. User documents library inside app data
      try {
        final appData = await AppDirectories.getAppDataDirectory();
        final libraryDir = Directory(p.join(appData.path, 'library'));
        if (await libraryDir.exists()) {
          dirsToScan.add(libraryDir);
        } else {
          await libraryDir.create(recursive: true);
          dirsToScan.add(libraryDir);
        }
      } catch (_) {}

      // 4. Conversation sessions outputs (generated artifacts & reports)
      try {
        final sessionsDir = await AppDirectories.getSessionsDirectory();
        if (await sessionsDir.exists()) dirsToScan.add(sessionsDir);
      } catch (_) {}

      for (final dir in dirsToScan) {
        try {
          final entities = dir.listSync(recursive: true, followLinks: false);
          for (final entity in entities) {
            if (entity is File && !visitedPaths.contains(entity.path)) {
              visitedPaths.add(entity.path);
              final basename = entity.path.split(Platform.pathSeparator).last;
              if (_isCodeOrInternalArtifact(entity.path, basename)) {
                continue;
              }

              final stat = await entity.stat();
              final ext = basename.contains('.')
                  ? basename.split('.').last.toLowerCase()
                  : '';

              final isImg = const {
                'png',
                'jpg',
                'jpeg',
                'webp',
                'gif',
                'bmp',
                'svg',
              }.contains(ext);
              final isMedia =
                  isImg ||
                  const {
                    'mp4',
                    'mov',
                    'mkv',
                    'mp3',
                    'wav',
                    'm4a',
                    'aac',
                    'flac',
                  }.contains(ext);
              final isApp = const {
                'apk',
                'app',
                'deb',
                'exe',
                'html',
                'pdf',
                'docx',
                'xlsx',
              }.contains(ext);

              loaded.add(
                LibraryItem(
                  file: entity,
                  name: basename,
                  size: stat.size,
                  modified: stat.modified,
                  isImage: isImg,
                  isMedia: isMedia,
                  isApp: isApp,
                ),
              );
            }
          }
        } catch (_) {}
      }

      loaded.sort((a, b) => b.modified.compareTo(a.modified));
      if (mounted) {
        setState(() {
          _items = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndAddFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        final uploadDir = await AppDirectories.getUploadDirectory();
        for (final platformFile in result.files) {
          if (platformFile.path != null) {
            final source = File(platformFile.path!);
            final targetPath =
                '${uploadDir.path}${Platform.pathSeparator}${platformFile.name}';
            await source.copy(targetPath);
          }
        }
        await _loadRealFiles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import file: $e')));
      }
    }
  }

  List<LibraryItem> get _filteredItems {
    return _items.where((item) {
      if (_searchQuery.isNotEmpty &&
          !item.name.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      switch (_currentTab) {
        case LibraryFilterTab.all:
          return true;
        case LibraryFilterTab.media:
          return item.isMedia;
        case LibraryFilterTab.apps:
          return item.isApp;
        case LibraryFilterTab.files:
          return !item.isMedia && !item.isApp;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Library',
          style: TextStyle(fontSize: 18, fontWeight: AppFontWeights.emphasis),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Filter Tabs (All | Media | Apps | Files)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterTab('All', LibraryFilterTab.all, cs),
                const SizedBox(width: 8),
                _buildFilterTab('Media', LibraryFilterTab.media, cs),
                const SizedBox(width: 8),
                _buildFilterTab('Apps', LibraryFilterTab.apps, cs),
                const SizedBox(width: 8),
                _buildFilterTab('Files', LibraryFilterTab.files, cs),
              ],
            ),
          ),

          // 2-Column Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Lucide.FolderClosed,
                          size: 48,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No items in library',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap + below to add files',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildGridCard(item, cs);
                    },
                  ),
          ),
        ],
      ),

      // Bottom Bar with ⋮ Menu, Search, and +
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // More menu button
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    Lucide.MoreVertical,
                    size: 20,
                    color: cs.onSurface,
                  ),
                  onPressed: () => _showMoreMenu(context),
                ),
              ),
              const SizedBox(width: 10),

              // Search Bar
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        Lucide.Search,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () => _searchController.clear(),
                          child: Icon(
                            Lucide.X,
                            size: 16,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // + Add File Button
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Lucide.Plus, size: 22, color: cs.onSurface),
                  onPressed: _pickAndAddFile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, LibraryFilterTab tab, ColorScheme cs) {
    final isSelected = _currentTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.onSurface.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected
                ? AppFontWeights.emphasis
                : FontWeight.normal,
            color: isSelected
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Future<void> _openLibraryItem(LibraryItem item) async {
    if (item.isImage) {
      final allImages = _filteredItems
          .where((e) => e.isImage)
          .map((e) => e.file.path)
          .toList();
      final idx = allImages.indexOf(item.file.path);
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, __, ___) => ImageViewerPage(
            images: allImages.isNotEmpty ? allImages : [item.file.path],
            initialIndex: idx >= 0 ? idx : 0,
          ),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
        ),
      );
      return;
    }

    final ext = p.extension(item.file.path).toLowerCase();
    if (ext == '.pdf') {
      await Navigator.of(
        context,
      ).push(PdfViewerPage.route(filePath: item.file.path, title: item.name));
      return;
    }

    await showFilePreview(context, item.file, title: item.name);
  }

  Widget _buildGridCard(LibraryItem item, ColorScheme cs) {
    final ext = p.extension(item.file.path).toLowerCase();
    final isPdf = ext == '.pdf';
    final typeStyle = previewFileTypeStyle(item.file.path);
    final extBadge = ext.replaceFirst('.', '').toUpperCase();

    return GestureDetector(
      onTap: () => _openLibraryItem(item),
      onLongPress: () => _showItemActions(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card thumbnail / file box
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.isImage
                  ? Hero(
                      tag: 'img:${item.file.path}',
                      child: Image.file(
                        item.file,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Lucide.FileImage,
                            size: 36,
                            color: typeStyle.color,
                          ),
                        ),
                      ),
                    )
                  : isPdf
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Colors.white,
                          child: AbsorbPointer(
                            child: SfPdfViewer.file(
                              item.file,
                              canShowScrollHead: false,
                              canShowScrollStatus: false,
                              canShowPaginationDialog: false,
                              enableDoubleTapZooming: false,
                              pageSpacing: 0,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD14D41),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PDF',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: typeStyle.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            typeStyle.icon,
                            size: 28,
                            color: typeStyle.color,
                          ),
                        ),
                        if (extBadge.isNotEmpty)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: typeStyle.color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                extBadge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: AppFontWeights.bold,
                                  color: typeStyle.color,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),

          // Date & Size
          Text(
            '${item.formattedDate} · ${item.formattedSize}',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  void _showItemActions(LibraryItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Lucide.Eye, color: cs.onSurface),
                title: Text('Preview ${item.name}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLibraryItem(item);
                },
              ),
              ListTile(
                leading: Icon(Lucide.Share2, color: cs.onSurface),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(item.file.path)],
                      subject: item.name,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Lucide.ExternalLink, color: cs.onSurface),
                title: const Text('Open with external app'),
                onTap: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(item.file.path);
                },
              ),
              ListTile(
                leading: const Icon(Lucide.Trash2, color: Colors.redAccent),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await item.file.delete();
                    await _loadRealFiles();
                  } catch (_) {}
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Lucide.RotateCw, color: cs.onSurface),
                title: const Text('Refresh'),
                onTap: () {
                  Navigator.pop(ctx);
                  _loadRealFiles();
                },
              ),
              ListTile(
                leading: Icon(Lucide.ArrowDownAZ, color: cs.onSurface),
                title: const Text('Sort by Name'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _items.sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
                  });
                },
              ),
              ListTile(
                leading: Icon(Lucide.Calendar, color: cs.onSurface),
                title: const Text('Sort by Date'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _items.sort((a, b) => b.modified.compareTo(a.modified));
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
