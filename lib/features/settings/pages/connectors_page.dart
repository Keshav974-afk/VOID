import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/composio/composio_models.dart';
import '../../../core/services/composio/composio_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class ConnectorsPage extends StatefulWidget {
  const ConnectorsPage({super.key});

  @override
  State<ConnectorsPage> createState() => _ConnectorsPageState();
}

class _ConnectorsPageState extends State<ConnectorsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  bool _editingApiKey = false;
  bool _validating = false;
  String? _storedApiKey;
  bool _loading = true;
  String? _authError;
  bool _isLive = false;
  String _selectedCategory = 'All';
  List<ComposioToolkit> _toolkits = [];

  final List<String> _categories = const [
    'All',
    'Productivity',
    'Developer Tools',
    'Communication',
    'CRM',
    'Social',
    'Finance',
    'Design',
    'AI & Automation',
    'Cloud & Storage',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final storedKey = await ComposioService.instance.getStoredApiKey();
    if (!mounted) return;
    setState(() {
      _storedApiKey = storedKey;
      if (storedKey != null && storedKey.isNotEmpty) {
        _apiKeyCtrl.text = storedKey;
      }
    });
    await _loadToolkits();
  }

  Future<void> _loadToolkits() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final list = await ComposioService.instance.fetchToolkits(
        apiKey: _storedApiKey,
        search: _searchCtrl.text.trim(),
        category: _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _toolkits = list;
          _authError = ComposioService.instance.lastAuthError;
          _isLive = ComposioService.instance.isLiveCatalog;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _authError = ComposioService.instance.lastAuthError;
          _isLive = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveApiKey() async {
    Haptics.light();
    final key = _apiKeyCtrl.text.trim();

    if (key.isEmpty) {
      await ComposioService.instance.setStoredApiKey('');
      if (!mounted) return;
      setState(() {
        _storedApiKey = null;
        _editingApiKey = false;
        _authError = null;
        _isLive = false;
      });
      showAppSnackBar(
        context,
        message: 'Composio API key removed',
        type: NotificationType.info,
      );
      _loadToolkits();
      return;
    }

    // Always immediately persist key to device storage so it is never lost
    await ComposioService.instance.setStoredApiKey(key);
    if (!mounted) return;
    setState(() {
      _storedApiKey = key;
      _editingApiKey = false;
    });

    setState(() => _validating = true);
    final validation = await ComposioService.instance.validateKey(key);
    if (!mounted) return;
    setState(() => _validating = false);

    if (!validation.isValid) {
      setState(() {
        _authError = validation.error;
        _isLive = false;
      });
      showAppSnackBar(
        context,
        message:
            'API key saved locally. Note: ${validation.error ?? "Offline"}',
        type: NotificationType.warning,
      );
      _loadToolkits();
      return;
    }

    // If consumer MCP key, auto-configure or update the Composio MCP server in Kelivo
    if (validation.isConsumer) {
      try {
        if (!mounted) return;
        final mcpProvider = Provider.of<McpProvider>(context, listen: false);
        final existing = mcpProvider.servers
            .where((s) => s.name.toLowerCase() == 'composio')
            .firstOrNull;
        if (existing == null) {
          await mcpProvider.addServer(
            enabled: true,
            name: 'Composio',
            transport: McpTransportType.http,
            url: 'https://connect.composio.dev/mcp',
            headers: {'x-consumer-api-key': key},
          );
        } else {
          await mcpProvider.updateServer(
            existing.copyWith(
              enabled: true,
              url: 'https://connect.composio.dev/mcp',
              headers: {'x-consumer-api-key': key},
            ),
          );
        }
      } catch (e) {
        debugPrint('[ConnectorsPage] MCP auto-config notice: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _storedApiKey = key;
      _editingApiKey = false;
      _authError = null;
      _isLive = true;
    });

    showAppSnackBar(
      context,
      message: validation.isConsumer
          ? 'Composio Consumer key validated & MCP connected!'
          : 'Composio Project API key validated & saved!',
      type: NotificationType.success,
    );
    _loadToolkits();
  }

  Future<void> _handleConnect(ComposioToolkit toolkit) async {
    Haptics.light();
    final pendingKey = _apiKeyCtrl.text.trim();
    if ((_storedApiKey == null || _storedApiKey!.isEmpty) &&
        pendingKey.isNotEmpty) {
      await _saveApiKey();
    }

    final effectiveKey =
        _storedApiKey ?? (pendingKey.isNotEmpty ? pendingKey : null);

    if (effectiveKey == null || effectiveKey.isEmpty) {
      if (!mounted) return;
      setState(() => _editingApiKey = true);
      showAppSnackBar(
        context,
        message: 'Please enter your Composio API key above first to connect.',
        type: NotificationType.warning,
      );
      return;
    }

    final ok = await ComposioService.instance.connectApp(
      toolkit.slug,
      apiKey: effectiveKey,
    );
    if (!mounted) return;
    if (ok) {
      showAppSnackBar(
        context,
        message: 'Opening authorization for ${toolkit.name}...',
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

    showAppSnackBar(
      context,
      message: 'Instruction copied to clipboard! Paste it into chat.',
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Connectors',
          style: TextStyle(
            fontSize: 18,
            fontWeight: AppFontWeights.emphasis,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Lucide.RefreshCw, size: 18, color: cs.onSurface),
            tooltip: 'Refresh',
            onPressed: () {
              Haptics.light();
              _loadToolkits();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Composio API Key Management Card
          _buildApiKeyCard(cs),
          const SizedBox(height: 16),

          // Search Field
          IosFormTextField(
            label: 'Search',
            controller: _searchCtrl,
            hintText: 'Search 500+ connectors (GitHub, Slack, Gmail)...',
            prefix: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Lucide.Search, size: 16, color: cs.onSurfaceVariant),
            ),
            suffix: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Lucide.X, size: 14, color: cs.onSurfaceVariant),
                    onPressed: () {
                      _searchCtrl.clear();
                      _loadToolkits();
                    },
                  )
                : null,
            onChanged: (_) => _loadToolkits(),
          ),
          const SizedBox(height: 12),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: isDark
                        ? const Color(0xFF27272A)
                        : cs.primaryContainer,
                    backgroundColor: isDark
                        ? const Color(0xFF18181B)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    checkmarkColor: isDark
                        ? const Color(0xFFF4F4F5)
                        : cs.onPrimaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? AppFontWeights.semibold
                          : AppFontWeights.regular,
                      color: isSelected
                          ? (isDark
                                ? const Color(0xFFF4F4F5)
                                : cs.onPrimaryContainer)
                          : (isDark
                                ? const Color(0xFFA1A1AA)
                                : cs.onSurfaceVariant),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? (isDark ? const Color(0xFF52525B) : cs.primary)
                          : (isDark
                                ? const Color(0xFF27272A)
                                : cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    onSelected: (_) {
                      Haptics.light();
                      setState(() => _selectedCategory = cat);
                      _loadToolkits();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Catalog Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Connectors',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurfaceVariant,
                  letterSpacing: -0.2,
                ),
              ),
              if (!_loading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF18181B)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF3F3F46)
                                : const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      '${_toolkits.length} apps',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Connectors list
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ),
            )
          else if (_toolkits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Lucide.Layers,
                      size: 32,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No connectors found',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Try adjusting your search or category filter',
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
                for (var i = 0; i < _toolkits.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? const Color(0xFF27272A)
                          : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _buildConnectorRow(_toolkits[i]),
                ],
              ],
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard(ColorScheme cs) {
    final hasKey = _storedApiKey != null && _storedApiKey!.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!hasKey || _editingApiKey) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF18181B) : cs.surfaceContainerLow,
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
                Icon(Lucide.KeyRound, size: 16, color: cs.onSurface),
                const SizedBox(width: 8),
                Text(
                  'Composio API Key',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://app.composio.dev/settings'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    'Get Key',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.medium,
                      color: cs.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your Composio API key to activate live OAuth connectors for 500+ apps.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            IosFormTextField(
              label: 'API Key',
              controller: _apiKeyCtrl,
              hintText: 'comp_live_... or ck_...',
              obscureText: true,
              onSubmitted: (_) => _saveApiKey(),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_editingApiKey && hasKey) ...[
                  IosTextButton(
                    label: 'Cancel',
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    onPressed: () {
                      setState(() {
                        _editingApiKey = false;
                        _apiKeyCtrl.text = _storedApiKey ?? '';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                IosTextButton(
                  label: _validating ? 'Checking...' : 'Save Key',
                  icon: _validating ? Lucide.Loader : Lucide.Check,
                  fontSize: 13,
                  color: cs.primary,
                  onPressed: _validating ? null : _saveApiKey,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final hasError = _authError != null;
    final masked = _storedApiKey!.length > 10
        ? '${_storedApiKey!.substring(0, 6)}...${_storedApiKey!.substring(_storedApiKey!.length - 4)}'
        : '••••••••';
    final isConsumerKey = _storedApiKey!.startsWith('ck_');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181B) : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                  : (isDark
                        ? const Color(0xFF27272A)
                        : cs.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasError
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          hasError
                              ? 'Key Needs Attention'
                              : (isConsumerKey
                                    ? 'Composio MCP Connected'
                                    : 'Composio Connected'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                        if (!hasError && isConsumerKey) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'MCP Live',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasError
                          ? _authError!
                          : '${isConsumerKey ? "Consumer MCP Key" : "Project Key"}: $masked',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasError
                            ? const Color(0xFFF59E0B)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IosTextButton(
                label: 'Change',
                icon: Lucide.Pencil,
                fontSize: 12,
                onPressed: () => setState(() => _editingApiKey = true),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF201608) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Lucide.BadgeInfo,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing offline catalog of ${_toolkits.length} apps. Check your API key at app.composio.dev/settings.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnectorRow(ComposioToolkit toolkit) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildLogo(toolkit),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            toolkit.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: AppFontWeights.emphasis,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (toolkit.isConnected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toolkit.category.isNotEmpty
                          ? toolkit.category
                          : 'General',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (toolkit.description != null &&
              toolkit.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              toolkit.description!,
              style: TextStyle(
                fontSize: 12,
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
              IosTextButton(
                label: 'Tell AI',
                icon: Lucide.Bot,
                fontSize: 12,
                color: cs.onSurfaceVariant,
                onPressed: () => _handleTellAi(toolkit),
              ),
              const SizedBox(width: 8),
              IosTextButton(
                label: toolkit.isConnected ? 'Reconnect' : 'Connect',
                icon: toolkit.isConnected ? Lucide.Check : Lucide.Link2,
                fontSize: 12,
                color: toolkit.isConnected
                    ? const Color(0xFF22C55E)
                    : cs.primary,
                onPressed: () => _handleConnect(toolkit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(ComposioToolkit toolkit) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoUrl = toolkit.logoUrl;
    final isSvg =
        logoUrl.toLowerCase().endsWith('.svg') ||
        logoUrl.contains('logos.composio.dev');

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
            : cs.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(7),
      alignment: Alignment.center,
      child: isSvg
          ? SvgPicture.network(
              logoUrl,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              placeholderBuilder: (_) =>
                  Icon(Lucide.Layers, size: 18, color: cs.onSurfaceVariant),
              errorBuilder: (_, __, ___) =>
                  Icon(Lucide.Layers, size: 18, color: cs.onSurfaceVariant),
            )
          : Image.network(
              logoUrl,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(Lucide.Layers, size: 18, color: cs.onSurfaceVariant),
            ),
    );
  }
}
