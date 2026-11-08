import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/haptics.dart';
import '../../../core/services/macros/void_macros_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class VoidMacrosPage extends StatefulWidget {
  const VoidMacrosPage({
    super.key,
    this.onRunMacro,
    this.recentUserPrompts = const [],
  });

  final ValueChanged<String>? onRunMacro;
  final List<String> recentUserPrompts;

  @override
  State<VoidMacrosPage> createState() => _VoidMacrosPageState();
}

class _VoidMacrosPageState extends State<VoidMacrosPage> {
  final VoidMacrosService _service = VoidMacrosService.instance;
  bool _loading = true;
  String _selectedCategory = 'All';

  static const List<String> _categories = [
    'All',
    'Custom',
    'Productivity',
    'Research',
    'Developer',
    'Strategy',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.ensureLoaded();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _recordFromRecentChat() async {
    Haptics.medium();
    final steps = widget.recentUserPrompts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(6)
        .toList();
    if (steps.isEmpty) {
      await _showCreateMacroDialog(
        initialTitle: 'Recorded Workflow',
        initialSteps: const [
          'Inspect active context and gather required inputs.',
          'Execute primary tool or browser actions.',
          'Verify results and summarize output.',
        ],
      );
      return;
    }
    await _showCreateMacroDialog(
      initialTitle: 'Recorded Session Workflow',
      initialDescription:
          'Recorded from ${steps.length} step(s) in active conversation.',
      initialSteps: steps,
    );
  }

  Future<void> _showCreateMacroDialog({
    String initialTitle = '',
    String initialDescription = '',
    List<String> initialSteps = const [],
  }) async {
    final titleCtrl = TextEditingController(text: initialTitle);
    final descCtrl = TextEditingController(text: initialDescription);
    final stepsCtrl = TextEditingController(
      text: initialSteps.isNotEmpty ? initialSteps.join('\n') : '',
    );
    final cs = Theme.of(context).colorScheme;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: Text(
          'Create / Record Agent Macro',
          style: TextStyle(
            fontSize: 17,
            fontWeight: AppFontWeights.emphasis,
            color: cs.onSurface,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IosFormTextField(
                  label: 'Macro Name',
                  controller: titleCtrl,
                  hintText: 'e.g. Daily Competitor Price Check',
                ),
                const SizedBox(height: 10),
                IosFormTextField(
                  label: 'Description',
                  controller: descCtrl,
                  hintText: 'What does this autonomous recipe do?',
                ),
                const SizedBox(height: 10),
                IosFormTextField(
                  label: 'Steps (one per line)',
                  controller: stepsCtrl,
                  hintText:
                      'Open browser to target dashboard\nExtract metrics table\nGenerate summary report',
                  maxLines: 6,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save Recipe'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final rawSteps = stepsCtrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (rawSteps.isEmpty) return;
      await _service.addMacro(
        title: titleCtrl.text,
        description: descCtrl.text,
        steps: rawSteps,
      );
      if (mounted) {
        setState(() {});
        showAppSnackBar(
          context,
          message: 'Agent Macro saved!',
          type: NotificationType.success,
        );
      }
    }
  }

  void _triggerMacro(VoidMacroRecipe macro) {
    Haptics.medium();
    final prompt = macro.buildExecutionPrompt();
    if (widget.onRunMacro != null) {
      widget.onRunMacro!(prompt);
      Navigator.of(context).maybePop();
      return;
    }
    Clipboard.setData(ClipboardData(text: prompt));
    showAppSnackBar(
      context,
      message:
          'Macro "${macro.title}" copied to clipboard! Paste in chat to run.',
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allMacros = _service.macros;
    final filtered = _selectedCategory == 'All'
        ? allMacros
        : allMacros
              .where(
                (m) =>
                    m.category.toLowerCase() == _selectedCategory.toLowerCase(),
              )
              .toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Agent Macros & Recipes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: AppFontWeights.emphasis,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Lucide.Disc, size: 18, color: cs.primary),
            tooltip: 'Record from Chat',
            onPressed: _recordFromRecentChat,
          ),
          IconButton(
            icon: Icon(Lucide.Plus, size: 18, color: cs.onSurface),
            tooltip: 'New Macro',
            onPressed: _showCreateMacroDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Record & Replay Banner
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
                          Icon(Lucide.Zap, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Record & Replay Autonomous Workflows',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.emphasis,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Chain Browser, Desktop/Phone Control, Search, and Connectors into 1-tap repeatable Agent Recipes.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IosTextButton(
                            label: 'Record Last Chat',
                            icon: Lucide.Disc,
                            onPressed: _recordFromRecentChat,
                          ),
                          const SizedBox(width: 8),
                          IosTextButton(
                            label: 'Create Recipe',
                            icon: Lucide.Plus,
                            onPressed: _showCreateMacroDialog,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Category filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final selected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat),
                          selected: selected,
                          selectedColor: isDark
                              ? const Color(0xFF27272A)
                              : cs.primaryContainer,
                          backgroundColor: isDark
                              ? const Color(0xFF18181B)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? AppFontWeights.semibold
                                : AppFontWeights.regular,
                            color: selected
                                ? (isDark
                                      ? const Color(0xFFF4F4F5)
                                      : cs.onPrimaryContainer)
                                : cs.onSurfaceVariant,
                          ),
                          onSelected: (_) {
                            Haptics.light();
                            setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                SectionCard(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      _buildMacroTile(filtered[i], cs),
                    ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildMacroTile(VoidMacroRecipe macro, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Lucide.Workflow, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  macro.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  macro.category,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            macro.description,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ...macro.steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${e.key + 1}. ${e.value}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!macro.isBuiltIn)
                IconButton(
                  icon: Icon(Lucide.Trash2, size: 16, color: cs.error),
                  onPressed: () async {
                    await _service.deleteMacro(macro.id);
                    if (mounted) setState(() {});
                  },
                ),
              IosTextButton(
                label: 'Run Macro',
                icon: Lucide.Play,
                fontSize: 12,
                onPressed: () => _triggerMacro(macro),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
