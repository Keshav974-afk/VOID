import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/services/composio/composio_models.dart';
import '../../../core/services/composio/composio_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class ComposioConnectorsSheet extends StatefulWidget {
  const ComposioConnectorsSheet({super.key, this.apiKey, this.onTellAi});

  final String? apiKey;
  final ValueChanged<String>? onTellAi;

  static Future<void> show(
    BuildContext context, {
    String? apiKey,
    ValueChanged<String>? onTellAi,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          ComposioConnectorsSheet(apiKey: apiKey, onTellAi: onTellAi),
    );
  }

  @override
  State<ComposioConnectorsSheet> createState() =>
      _ComposioConnectorsSheetState();
}

class _ComposioConnectorsSheetState extends State<ComposioConnectorsSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ComposioToolkit> _toolkits = [];
  bool _loading = true;
  String _selectedCategory = 'All';
  String? _effectiveKey;

  final List<String> _categories = const [
    'All',
    'Productivity',
    'Developer Tools',
    'Communication',
    'CRM',
    'Social',
    'Finance',
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    _effectiveKey = await ComposioService.instance.resolveApiKey(
      explicitKey: widget.apiKey,
    );
    await _loadToolkits();
  }

  Future<void> _loadToolkits() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final list = await ComposioService.instance.fetchToolkits(
        apiKey: _effectiveKey,
        search: _searchCtrl.text.trim(),
        category: _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _toolkits = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleConnect(ComposioToolkit toolkit) async {
    Haptics.light();
    final ok = await ComposioService.instance.connectApp(
      toolkit.slug,
      apiKey: _effectiveKey,
    );
    if (!mounted) return;
    if (ok) {
      showAppSnackBar(
        context,
        message: 'Opening authentication for ${toolkit.name}...',
        type: NotificationType.info,
      );
    } else {
      showAppSnackBar(
        context,
        message: 'Could not open authorization page for ${toolkit.name}',
        type: NotificationType.error,
      );
    }
  }

  void _handleTellAi(ComposioToolkit toolkit) {
    Haptics.medium();
    final prompt = ComposioService.instance.getAiConnectPrompt(toolkit);
    Clipboard.setData(ClipboardData(text: prompt));

    if (widget.onTellAi != null) {
      widget.onTellAi!(prompt);
      Navigator.of(context).pop();
    } else {
      showAppSnackBar(
        context,
        message: 'Copied prompt to clipboard! Paste it to your AI agent.',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF27272A)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Lucide.Layers, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Composio Connectors',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Connect 500+ SaaS apps or delegate setup to AI',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Lucide.RefreshCw, size: 16, color: cs.onSurface),
                    onPressed: _loadToolkits,
                  ),
                  IconButton(
                    icon: Icon(Lucide.X, size: 18, color: cs.onSurface),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IosFormTextField(
                label: 'Search',
                controller: _searchCtrl,
                hintText: 'Search connectors (e.g. GitHub, Slack, Gmail)...',
                prefix: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Lucide.Search,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                suffix: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Lucide.X,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadToolkits();
                        },
                      )
                    : null,
                onChanged: (_) => _loadToolkits(),
              ),
            ),
            const SizedBox(height: 10),

            // Category filter chips
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, index) {
                  final cat = _categories[index];
                  final selected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedCategory = cat);
                        _loadToolkits();
                      }
                    },
                    selectedColor: isDark
                        ? const Color(0xFF27272A)
                        : cs.primaryContainer,
                    backgroundColor: isDark
                        ? const Color(0xFF18181B)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? AppFontWeights.emphasis
                          : FontWeight.normal,
                      color: selected
                          ? (isDark
                                ? const Color(0xFFF4F4F5)
                                : cs.onPrimaryContainer)
                          : (isDark
                                ? const Color(0xFFA1A1AA)
                                : cs.onSurfaceVariant),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: selected
                            ? (isDark ? const Color(0xFF52525B) : cs.primary)
                            : (isDark
                                  ? const Color(0xFF27272A)
                                  : cs.outlineVariant.withValues(alpha: 0.6)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Toolkits list
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    )
                  : _toolkits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Lucide.SearchX,
                            size: 36,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No matching connectors found',
                            style: TextStyle(fontSize: 14, color: cs.onSurface),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _toolkits.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, index) {
                        final item = _toolkits[index];
                        return _buildConnectorCard(context, item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectorCard(BuildContext context, ComposioToolkit item) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
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
              // Logo
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.transparent
                        : cs.outlineVariant.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                child:
                    item.logoUrl.toLowerCase().endsWith('.svg') ||
                        item.logoUrl.contains('logos.composio.dev')
                    ? SvgPicture.network(
                        item.logoUrl,
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                        placeholderBuilder: (_) => Icon(
                          Lucide.Layers,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        errorBuilder: (_, __, ___) => Icon(
                          Lucide.Layers,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : Image.network(
                        item.logoUrl,
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Lucide.Layers,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Name and Category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (item.isConnected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF052E16)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF86EFAC),
                              ),
                            ),
                            child: Text(
                              'CONNECTED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: AppFontWeights.emphasis,
                                color: isDark
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.category}${item.toolCount > 0 ? " · ${item.toolCount} tools" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.description!,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Tell AI button
              IosTextButton(
                label: 'Tell AI to Connect',
                icon: Lucide.Bot,
                fontSize: 12,
                color: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onPressed: () => _handleTellAi(item),
              ),
              const SizedBox(width: 8),
              // Connect button
              IosTextButton(
                label: item.isConnected ? 'Connected' : 'Connect',
                icon: item.isConnected ? Lucide.Check : Lucide.ExternalLink,
                fontSize: 12,
                color: item.isConnected ? const Color(0xFF22C55E) : cs.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                onPressed: () => _handleConnect(item),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
