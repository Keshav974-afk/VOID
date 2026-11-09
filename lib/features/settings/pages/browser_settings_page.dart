import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/services/browser/browser_service.dart';
import '../../../core/services/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../browser/browser_navigation.dart';
import '../../browser/models/browser_models.dart';

class BrowserSettingsPage extends StatefulWidget {
  const BrowserSettingsPage({super.key});

  @override
  State<BrowserSettingsPage> createState() => _BrowserSettingsPageState();
}

class _BrowserSettingsPageState extends State<BrowserSettingsPage> {
  final _service = BrowserService.instance;

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  Future<void> _update(BrowserSettings next) async {
    try {
      await _service.updateSettings(next);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settings: $e')),
        );
      }
    }
  }

  Widget _iosSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6, top: 18),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: AppFontWeights.emphasis,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _iosSwitchRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: cs.primary,
            onChanged: (v) {
              Haptics.light();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _iosNavRow({
    required IconData icon,
    required String label,
    String? detailText,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: iconColor ?? (isDestructive ? cs.error : cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: isDestructive ? cs.error : cs.onSurface,
                ),
              ),
            ),
            if (detailText != null)
              Text(
                detailText,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            const SizedBox(width: 6),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iosDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 48,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
    );
  }

  Future<void> _chooseSearchEngine() async {
    final s = _service.settings;
    final selected = await showModalBottomSheet<BrowserSearchEngine>(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Select Search Engine',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final engine in BrowserSearchEngine.values)
                ListTile(
                  leading: const Icon(LucideIcons.search, size: 20),
                  title: Text(engine.name.toUpperCase()),
                  trailing: s.searchEngine == engine
                      ? const Icon(LucideIcons.check, color: Colors.blue)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(engine),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await _update(s.copyWith(searchEngine: selected));
    }
  }

  Future<void> _chooseUserAgent() async {
    final s = _service.settings;
    final controller = TextEditingController(text: s.customUserAgent);
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom User-Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Leave empty to use standard mobile/desktop User-Agent preset.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Mozilla/5.0 ...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res != null) {
      await _update(s.copyWith(customUserAgent: res));
    }
  }

  Future<void> _manageCustomExtensions() async {
    final s = _service.settings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'User Extensions / Scripts',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus),
                        onPressed: () async {
                          final newExt = await _showAddExtensionDialog();
                          if (newExt != null) {
                            final updated = List<BrowserExtension>.from(
                              s.extensions,
                            )..add(newExt);
                            await _update(s.copyWith(extensions: updated));
                            setModalState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Installed UserScripts and extensions automatically execute on web pages.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: s.extensions.isEmpty
                        ? const Center(
                            child: Text('No custom extensions added yet.'),
                          )
                        : ListView.separated(
                            itemCount: s.extensions.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final ext = s.extensions[index];
                              return ListTile(
                                leading: const Icon(LucideIcons.puzzle),
                                title: Text(ext.name),
                                subtitle: Text(
                                  ext.description.isNotEmpty
                                      ? ext.description
                                      : 'Match: ${ext.matchPattern}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch.adaptive(
                                      value: ext.isEnabled,
                                      onChanged: (v) async {
                                        final updated =
                                            List<BrowserExtension>.from(
                                              s.extensions,
                                            );
                                        updated[index] = ext.copyWith(
                                          isEnabled: v,
                                        );
                                        await _update(
                                          s.copyWith(extensions: updated),
                                        );
                                        setModalState(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        LucideIcons.trash2,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        final updated =
                                            List<BrowserExtension>.from(
                                              s.extensions,
                                            )..removeAt(index);
                                        await _update(
                                          s.copyWith(extensions: updated),
                                        );
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<BrowserExtension?> _showAddExtensionDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final scriptCtrl = TextEditingController();

    return showDialog<BrowserExtension>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add User Extension'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'My Userscript',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional description',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scriptCtrl,
                decoration: const InputDecoration(
                  labelText: 'JavaScript Code',
                  hintText: 'console.log("Hello from extension!");',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  scriptCtrl.text.trim().isEmpty)
                return;
              Navigator.of(ctx).pop(
                BrowserExtension(
                  id: 'ext-${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  script: scriptCtrl.text.trim(),
                  isEnabled: true,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearWebsiteData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Website Data?'),
        content: const Text(
          'This will remove all cookies, site cache, web storage, and session data. Active logins will be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.clearWebsiteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Website data cleared successfully.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final s = _service.settings;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Browser Settings'),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.externalLink),
                tooltip: 'Open Browser',
                onPressed: () => openBrowserPage(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Launch Card
              Card(
                elevation: 0,
                color: cs.primaryContainer.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          LucideIcons.globe,
                          size: 28,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chromium Engine',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: AppFontWeights.emphasis,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              Platform.isAndroid
                                  ? 'Android Chromium WebView'
                                  : Platform.isWindows
                                  ? 'Microsoft WebView2 (Chromium)'
                                  : 'Native WebKit Engine',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => openBrowserPage(context),
                        icon: const Icon(LucideIcons.compass, size: 16),
                        label: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ),

              // Privacy & Incognito Section
              _iosSectionHeader('Privacy & Incognito'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _iosSwitchRow(
                      icon: LucideIcons.venetianMask,
                      label: 'Incognito Mode by Default',
                      subtitle:
                          'Browse without saving history, cache, or permanent cookies.',
                      value: s.incognitoDefault,
                      onChanged: (v) =>
                          _update(s.copyWith(incognitoDefault: v)),
                    ),
                    _iosDivider(),
                    _iosSwitchRow(
                      icon: LucideIcons.history,
                      label: 'Save Browsing History',
                      subtitle: 'Keep a searchable record of visited websites.',
                      value: s.saveHistory,
                      onChanged: (v) => _update(s.copyWith(saveHistory: v)),
                    ),
                    _iosDivider(),
                    _iosSwitchRow(
                      icon: LucideIcons.panelsTopLeft,
                      label: 'Restore Tabs on Launch',
                      subtitle:
                          'Reopen non-incognito tabs when starting the app.',
                      value: s.restoreTabs,
                      onChanged: (v) => _update(s.copyWith(restoreTabs: v)),
                    ),
                  ],
                ),
              ),

              // Chromium DevTools Section
              _iosSectionHeader('Chromium Developer Tools'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _iosSwitchRow(
                      icon: LucideIcons.codeXml,
                      label: 'Inspectable WebEngine & DevTools',
                      subtitle: Platform.isAndroid
                          ? 'Enables chrome://inspect ADB debugging and in-page Chromium DevTools.'
                          : 'Enables native Chromium DevTools window and in-page inspector.',
                      value: s.devToolsEnabled,
                      onChanged: (v) => _update(s.copyWith(devToolsEnabled: v)),
                    ),
                    _iosDivider(),
                    _iosNavRow(
                      icon: LucideIcons.terminal,
                      label: 'Open DevTools on Active Page',
                      detailText: _service.activeTab != null
                          ? 'Active'
                          : 'No page open',
                      onTap: () async {
                        if (_service.activeTab == null) {
                          await openBrowserPage(context);
                        }
                        await _service.openDevTools();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Platform.isAndroid
                                    ? 'DevTools active! Connect PC to chrome://inspect or use the in-page inspector.'
                                    : 'Native Chromium DevTools window opened.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Extensions Section
              _iosSectionHeader('Extensions & Shields'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _iosSwitchRow(
                      icon: LucideIcons.shieldAlert,
                      label: 'AdBlock Shield',
                      subtitle:
                          'Automatically hides intrusive ads, banners, and tracking frames.',
                      value: s.adBlockEnabled,
                      onChanged: (v) => _update(s.copyWith(adBlockEnabled: v)),
                    ),
                    _iosDivider(),
                    _iosSwitchRow(
                      icon: LucideIcons.moon,
                      label: 'Dark Mode Enforcer',
                      subtitle:
                          'Enforce high-contrast dark theme across all web pages.',
                      value: s.darkModeEnabled,
                      onChanged: (v) => _update(s.copyWith(darkModeEnabled: v)),
                    ),
                    _iosDivider(),
                    _iosNavRow(
                      icon: LucideIcons.puzzle,
                      label: 'User Extensions & Scripts',
                      detailText: '${s.extensions.length} installed',
                      onTap: _manageCustomExtensions,
                    ),
                  ],
                ),
              ),

              // Engine Configuration
              _iosSectionHeader('General Preferences'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _iosNavRow(
                      icon: LucideIcons.search,
                      label: 'Default Search Engine',
                      detailText: s.searchEngine.name.toUpperCase(),
                      onTap: _chooseSearchEngine,
                    ),
                    _iosDivider(),
                    _iosSwitchRow(
                      icon: LucideIcons.monitor,
                      label: 'Desktop Mode',
                      subtitle: 'Request desktop layout by default.',
                      value: s.desktopMode,
                      onChanged: (v) => _update(s.copyWith(desktopMode: v)),
                    ),
                    _iosDivider(),
                    _iosNavRow(
                      icon: LucideIcons.user,
                      label: 'User-Agent String',
                      detailText: s.customUserAgent.isNotEmpty
                          ? 'Custom'
                          : 'Default',
                      onTap: _chooseUserAgent,
                    ),
                    _iosDivider(),
                    _iosSwitchRow(
                      icon: LucideIcons.bot,
                      label: 'AI Web Autonomous Agent',
                      subtitle:
                          'Allow VOID AI assistants to browse and interact with pages.',
                      value: s.agentEnabled,
                      onChanged: (v) => _update(s.copyWith(agentEnabled: v)),
                    ),
                  ],
                ),
              ),

              // Data Management
              _iosSectionHeader('Data Management'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _iosNavRow(
                      icon: LucideIcons.trash2,
                      label: 'Clear Website Data & Cache',
                      detailText: 'Cookies, Cache, Storage',
                      isDestructive: true,
                      onTap: _clearWebsiteData,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
