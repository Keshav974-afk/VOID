import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';
import '../../../core/services/vault/void_knowledge_vault_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class VoidKnowledgeVaultPage extends StatefulWidget {
  const VoidKnowledgeVaultPage({super.key, this.onInsertContext});

  final ValueChanged<String>? onInsertContext;

  @override
  State<VoidKnowledgeVaultPage> createState() => _VoidKnowledgeVaultPageState();
}

class _VoidKnowledgeVaultPageState extends State<VoidKnowledgeVaultPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final VoidKnowledgeVaultService _vault = VoidKnowledgeVaultService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _vault.ensureLoaded();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _importFiles() async {
    Haptics.light();
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'markdown',
          'json',
          'csv',
          'dart',
          'py',
          'js',
          'ts',
          'html',
          'css',
          'xml',
          'yaml',
          'yml',
          'log',
        ],
      );
      if (result == null || result.files.isEmpty) return;

      var count = 0;
      for (final pf in result.files) {
        final path = pf.path;
        if (path == null) continue;
        final doc = await _vault.importFile(File(path));
        if (doc != null) count++;
      }
      if (!mounted) return;
      setState(() {});
      showAppSnackBar(
        context,
        message: count > 0
            ? 'Indexed $count document(s) into Knowledge Vault'
            : 'Could not read text from selected file(s)',
        type: count > 0 ? NotificationType.success : NotificationType.warning,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Import failed: $e',
        type: NotificationType.error,
      );
    }
  }

  Future<void> _showAddNoteDialog() async {
    Haptics.light();
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: Text(
          'Add Knowledge Note',
          style: TextStyle(
            fontSize: 17,
            fontWeight: AppFontWeights.emphasis,
            color: cs.onSurface,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IosFormTextField(
                label: 'Title',
                controller: titleCtrl,
                hintText: 'e.g. Project Architecture / API Specs',
              ),
              const SizedBox(height: 12),
              IosFormTextField(
                label: 'Content',
                controller: contentCtrl,
                hintText: 'Paste documentation, notes, or reference text...',
                maxLines: 7,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save to Vault'),
          ),
        ],
      ),
    );

    if (saved == true && contentCtrl.text.trim().isNotEmpty) {
      await _vault.addNote(
        title: titleCtrl.text.trim().isEmpty
            ? 'Knowledge Note'
            : titleCtrl.text.trim(),
        content: contentCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {});
        showAppSnackBar(
          context,
          message: 'Saved to Local Knowledge Vault',
          type: NotificationType.success,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queryText = _searchCtrl.text.trim();
    final docs = _vault.documents;
    final hits = queryText.isNotEmpty
        ? _vault.query(queryText, topK: 8)
        : const <VaultChunkHit>[];

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Knowledge Vault (Local RAG)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: AppFontWeights.emphasis,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Lucide.FilePlus, size: 18, color: cs.onSurface),
            tooltip: 'Add Note',
            onPressed: _showAddNoteDialog,
          ),
          IconButton(
            icon: Icon(Lucide.Upload, size: 18, color: cs.onSurface),
            tooltip: 'Import Files',
            onPressed: _importFiles,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Header card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF18181B)
                        : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF27272A)
                          : cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Lucide.Database, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Private On-Device RAG Index',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: AppFontWeights.emphasis,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _vault.autoInjectInChat,
                            onChanged: (val) async {
                              Haptics.light();
                              await _vault.setAutoInjectInChat(val);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Index local documents, notes, and code files on-device. When enabled, VOID automatically retrieves and cites matching excerpts during chat.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IosTextButton(
                            label: 'Import Files',
                            icon: Lucide.Upload,
                            onPressed: _importFiles,
                          ),
                          const SizedBox(width: 8),
                          IosTextButton(
                            label: 'New Note',
                            icon: Lucide.Plus,
                            onPressed: _showAddNoteDialog,
                          ),
                          const Spacer(),
                          Text(
                            '${docs.length} docs indexed',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Semantic / Lexical Search Test
                IosFormTextField(
                  label: 'Search Vault',
                  controller: _searchCtrl,
                  hintText:
                      'Test retrieval query across your indexed documents...',
                  prefix: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Lucide.Search,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  suffix: queryText.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Lucide.X,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                if (queryText.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Retrieved Passages (${hits.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (hits.isNotEmpty && widget.onInsertContext != null)
                        IosTextButton(
                          label: 'Attach to Chat',
                          icon: Lucide.Send,
                          fontSize: 12,
                          onPressed: () {
                            final ctxPrompt = _vault.buildContextPrompt(
                              queryText,
                            );
                            widget.onInsertContext!(ctxPrompt);
                            Navigator.of(context).maybePop();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hits.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No matching excerpts found',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    SectionCard(
                      children: [
                        for (var i = 0; i < hits.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Lucide.FileText,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        hits[i].document.title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: AppFontWeights.emphasis,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Score: ${hits[i].score.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  hits[i].excerpt,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                ],

                Text(
                  'Indexed Documents',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Lucide.FolderOpen,
                            size: 36,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your Knowledge Vault is empty',
                            style: TextStyle(fontSize: 14, color: cs.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Import Markdown, text, JSON, or source code files to ground VOID in your private knowledge.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SectionCard(
                    children: [
                      for (var i = 0; i < docs.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ListTile(
                          leading: Icon(
                            Lucide.FileText,
                            size: 20,
                            color: cs.primary,
                          ),
                          title: Text(
                            docs[i].title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.emphasis,
                              color: cs.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${docs[i].wordCount} words · ${docs[i].content.length} chars',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onInsertContext != null)
                                IconButton(
                                  icon: Icon(
                                    Lucide.MessageSquarePlus,
                                    size: 17,
                                    color: cs.primary,
                                  ),
                                  tooltip: 'Use in Chat',
                                  onPressed: () {
                                    final prompt = _vault.buildContextPrompt(
                                      docs[i].title,
                                    );
                                    widget.onInsertContext!(prompt);
                                    Navigator.of(context).maybePop();
                                  },
                                ),
                              IconButton(
                                icon: Icon(
                                  Lucide.Trash2,
                                  size: 17,
                                  color: cs.error,
                                ),
                                tooltip: 'Remove',
                                onPressed: () async {
                                  await _vault.removeDocument(docs[i].id);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
    );
  }
}
