import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/app_directories.dart';

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

  Future<void> _loadRealFiles() async {
    setState(() => _isLoading = true);
    try {
      final Set<String> visitedPaths = {};
      final List<LibraryItem> loaded = [];

      final dirsToScan = <Directory>[];

      try {
        final uploadDir = await AppDirectories.getUploadDirectory();
        if (await uploadDir.exists()) dirsToScan.add(uploadDir);
      } catch (_) {}

      try {
        final imagesDir = await AppDirectories.getImagesDirectory();
        if (await imagesDir.exists()) dirsToScan.add(imagesDir);
      } catch (_) {}

      try {
        final workspacesDir = await AppDirectories.getWorkspacesDirectory();
        if (await workspacesDir.exists()) dirsToScan.add(workspacesDir);
      } catch (_) {}

      for (final dir in dirsToScan) {
        try {
          final entities = dir.listSync(recursive: true, followLinks: false);
          for (final entity in entities) {
            if (entity is File && !visitedPaths.contains(entity.path)) {
              visitedPaths.add(entity.path);
              final basename = entity.path.split(Platform.pathSeparator).last;
              if (basename.startsWith('.')) continue;

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
                'sh',
                'py',
                'js',
                'ts',
                'html',
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

  Widget _buildGridCard(LibraryItem item, ColorScheme cs) {
    return GestureDetector(
      onTap: () => OpenFilex.open(item.file.path),
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
              ),
              clipBehavior: Clip.antiAlias,
              child: item.isImage
                  ? Image.file(
                      item.file,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          Lucide.FileImage,
                          size: 36,
                          color: cs.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Lucide.File,
                        size: 38,
                        color: cs.onSurface.withValues(alpha: 0.35),
                      ),
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
                leading: Icon(Lucide.ExternalLink, color: cs.onSurface),
                title: Text('Open ${item.name}'),
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
