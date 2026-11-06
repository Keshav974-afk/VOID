import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/services/desktop_control/desktop_control_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class DesktopControlSettingsPage extends StatefulWidget {
  const DesktopControlSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const DesktopControlSettingsPage()),
    );
  }

  @override
  State<DesktopControlSettingsPage> createState() =>
      _DesktopControlSettingsPageState();
}

class _DesktopControlSettingsPageState
    extends State<DesktopControlSettingsPage> {
  DesktopSystemOverview? _overview;
  List<DesktopWindowInfo> _windows = const [];
  bool _loading = true;
  String? _lastActionMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final overview = await DesktopControlService.instance.getSystemOverview();
      final windows = await DesktopControlService.instance.listOpenWindows();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _windows = windows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _runQuickAction(
    String label,
    Future<String> Function() action,
  ) async {
    Haptics.light();
    setState(() => _lastActionMessage = 'Running "$label"...');
    try {
      final raw = await action();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? 'ok';
      final msg =
          decoded['message']?.toString() ??
          decoded['file_path']?.toString() ??
          '$label completed ($status)';
      if (!mounted) return;
      setState(() => _lastActionMessage = msg);
      showAppSnackBar(
        context,
        message: msg,
        type: status == 'ok'
            ? NotificationType.success
            : NotificationType.warning,
      );
      unawaited(_refresh());
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastActionMessage = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _buildHeroBanner(context, cs),
              const SizedBox(height: 16),
              _buildSystemTelemetryCard(context, cs),
              const SizedBox(height: 16),
              _buildQuickActionsSection(context, cs),
              if (_lastActionMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Lucide.Terminal, size: 16, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastActionMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withValues(alpha: 0.88),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildOpenWindowsSection(context, cs),
              const SizedBox(height: 16),
              _buildCapabilitiesSection(context, cs),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return Scaffold(backgroundColor: Colors.transparent, body: body);
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Desktop & System Control'),
        leading: IosIconButton(
          icon: LucideIcons.arrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          tooltip: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IosIconButton(
            icon: LucideIcons.refreshCw,
            color: cs.onSurface,
            size: 20,
            minSize: 44,
            semanticLabel: 'Refresh',
            tooltip: 'Refresh System Telemetry',
            onTap: _refresh,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildHeroBanner(BuildContext context, ColorScheme cs) {
    final isDesktop = DesktopControlService.isDesktopPlatform;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.14),
            cs.primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isDesktop ? Lucide.Monitor : Lucide.Smartphone,
              size: 24,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Universal Device & Desktop Control',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: AppFontWeights.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Allows the AI assistant to inspect windows, launch apps, take screenshots, automate mouse & keyboard, and manage system audio across Windows, macOS, Linux, Android, and iOS.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          if (widget.embedded)
            IconButton(
              icon: const Icon(Lucide.RefreshCw, size: 18),
              tooltip: 'Refresh Telemetry',
              onPressed: _refresh,
            ),
        ],
      ),
    );
  }

  Widget _buildSystemTelemetryCard(BuildContext context, ColorScheme cs) {
    final ov = _overview;
    if (_loading && ov == null) {
      return const SectionCard(
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      );
    }
    if (ov == null) return const SizedBox.shrink();

    final memRatio = (ov.memoryUsagePercent / 100.0).clamp(0.0, 1.0);
    final usedGb = (ov.usedMemoryMb / 1024).toStringAsFixed(1);
    final totalGb = (ov.totalMemoryMb / 1024).toStringAsFixed(1);

    final hasDisk = ov.diskTotalGb != null && ov.diskTotalGb! > 0;
    final diskUsedGb = hasDisk
        ? (ov.diskTotalGb! - (ov.diskFreeGb ?? 0)).clamp(0.0, ov.diskTotalGb!)
        : 0.0;
    final diskRatio = hasDisk
        ? (diskUsedGb / ov.diskTotalGb!).clamp(0.0, 1.0)
        : 0.0;

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.Cpu, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Live System Telemetry',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${ov.username}@${ov.hostname}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metricChip(
                    cs,
                    icon: Lucide.Monitor,
                    label: 'OS',
                    value: ov.platform.toUpperCase(),
                  ),
                  _metricChip(
                    cs,
                    icon: Lucide.Cpu,
                    label: 'CPU Cores',
                    value: '${ov.cpuCores} Logical',
                  ),
                  if (ov.screenWidth != null && ov.screenHeight != null)
                    _metricChip(
                      cs,
                      icon: Lucide.Maximize2,
                      label: 'Display',
                      value: '${ov.screenWidth}×${ov.screenHeight}',
                    ),
                  if (ov.batteryPercent != null)
                    _metricChip(
                      cs,
                      icon: Lucide.BatteryCharging,
                      label: 'Battery',
                      value:
                          '${ov.batteryPercent}%${ov.isCharging == true ? ' ⚡' : ''}',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Memory Progress
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Memory (RAM)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    '$usedGb GB / $totalGb GB (${ov.memoryUsagePercent.toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: memRatio,
                  minHeight: 7,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    memRatio > 0.85 ? cs.error : cs.primary,
                  ),
                ),
              ),
              if (hasDisk) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Primary Disk Storage',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      '${diskUsedGb.toStringAsFixed(1)} GB / ${ov.diskTotalGb!.toStringAsFixed(1)} GB',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: diskRatio,
                    minHeight: 7,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      diskRatio > 0.90 ? cs.error : const Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricChip(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context, ColorScheme cs) {
    final actions =
        <({IconData icon, String label, Future<String> Function() run})>[
          (
            icon: Lucide.Camera,
            label: 'Take Screenshot',
            run: () => DesktopControlService.instance.executeAction({
              'action': 'screenshot',
            }),
          ),
          (
            icon: Lucide.AppWindow,
            label: 'Scan Windows',
            run: () => DesktopControlService.instance.executeAction({
              'action': 'list_windows',
            }),
          ),
          (
            icon: Lucide.VolumeX,
            label: 'Mute / Unmute',
            run: () => DesktopControlService.instance.executeAction({
              'action': 'volume',
              'media_action': 'mute',
            }),
          ),
          (
            icon: Lucide.Terminal,
            label: 'Open Terminal',
            run: () => DesktopControlService.instance.executeAction({
              'action': 'open_app',
              'app_name': 'terminal',
            }),
          ),
          (
            icon: Lucide.Folder,
            label: 'Open Files',
            run: () => DesktopControlService.instance.executeAction({
              'action': 'open_app',
              'app_name': 'explorer',
            }),
          ),
          (
            icon: Lucide.ClipboardCopy,
            label: 'Copy System JSON',
            run: () async {
              final info = await DesktopControlService.instance
                  .getSystemOverview();
              final jsonStr = const JsonEncoder.withIndent(
                '  ',
              ).convert(info.toJson());
              await Clipboard.setData(ClipboardData(text: jsonStr));
              return jsonEncode({
                'status': 'ok',
                'message': 'System telemetry copied to clipboard.',
              });
            },
          ),
        ];

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.Zap, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Control Actions',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final act in actions)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _runQuickAction(act.label, act.run),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(act.icon, size: 16, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              act.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOpenWindowsSection(BuildContext context, ColorScheme cs) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.Layers, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Active Desktop Windows (${_windows.length})',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_windows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    DesktopControlService.isDesktopPlatform
                        ? 'No desktop windows detected or refresh in progress.'
                        : 'Window enumeration is active on desktop platforms (Windows, macOS, Linux).',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              else
                ..._windows.take(12).map((w) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: w.isActive
                                ? cs.primary.withValues(alpha: 0.15)
                                : cs.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Lucide.AppWindow,
                            size: 16,
                            color: w.isActive
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: w.isActive
                                      ? AppFontWeights.semibold
                                      : AppFontWeights.regular,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                '${w.processName} · PID ${w.pid}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _runQuickAction(
                            'Focus ${w.processName}',
                            () => DesktopControlService.instance.executeAction({
                              'action': 'focus_window',
                              'pid': w.pid,
                              'window_title': w.title,
                            }),
                          ),
                          child: const Text('Focus'),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilitiesSection(BuildContext context, ColorScheme cs) {
    const items = [
      (
        Lucide.AppWindow,
        'Window & Screen Inspection',
        'Lists all open windows, titles, PIDs, and captures full-resolution screenshots.',
      ),
      (
        Lucide.MousePointerClick,
        'Mouse & Cursor Automation',
        'Supports left, right, double-click, cursor movement, and scroll wheel automation.',
      ),
      (
        Lucide.Keyboard,
        'Keyboard & Shortcut Injection',
        'Types text directly into focused apps and triggers system hotkeys (Ctrl+C, Alt+Tab, Enter).',
      ),
      (
        Lucide.Rocket,
        'App & URL Launcher',
        'Opens desktop applications, system settings, directories, and external URLs.',
      ),
    ];

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supported Capabilities (desktop_control)',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$1, size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: AppFontWeights.semibold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$3,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: cs.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
