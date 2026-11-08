import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../mcp/pages/mcp_page.dart';
import '../../../core/models/vps_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/sandbox_vps/sandbox_vps_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// Settings page for configuring the Sandbox VPS / SSH Server connection.
class VpsSettingsPage extends StatefulWidget {
  const VpsSettingsPage({super.key});

  @override
  State<VpsSettingsPage> createState() => _VpsSettingsPageState();
}

class _VpsSettingsPageState extends State<VpsSettingsPage> {
  late final TextEditingController _hostCtl;
  late final TextEditingController _portCtl;
  late final TextEditingController _userCtl;
  late final TextEditingController _passCtl;
  late final TextEditingController _cwdCtl;
  late final TextEditingController _timeoutCtl;
  late final TextEditingController _testCmdCtl;

  final FocusNode _hostFn = FocusNode();
  final FocusNode _portFn = FocusNode();
  final FocusNode _userFn = FocusNode();
  final FocusNode _passFn = FocusNode();
  final FocusNode _cwdFn = FocusNode();
  final FocusNode _timeoutFn = FocusNode();

  bool _enabled = true;
  bool _obscurePassword = true;

  // Test connection state
  bool _testingConnection = false;
  bool? _connectionOk;
  int? _latencyMs;
  String? _connectionInfo;
  String? _connectionError;

  // Test command state
  bool _runningCommand = false;
  SandboxVpsToolResult? _cmdResult;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    final cfg = sp.vpsConfig;
    _enabled = cfg.enabled;
    _hostCtl = TextEditingController(text: cfg.host);
    _portCtl = TextEditingController(text: cfg.port.toString());
    _userCtl = TextEditingController(text: cfg.username);
    _passCtl = TextEditingController(text: cfg.password);
    _cwdCtl = TextEditingController(text: cfg.defaultCwd);
    _timeoutCtl = TextEditingController(text: cfg.timeoutSeconds.toString());
    _testCmdCtl = TextEditingController(text: 'uname -a && uptime');

    _hostFn.addListener(_save);
    _portFn.addListener(_save);
    _userFn.addListener(_save);
    _passFn.addListener(_save);
    _cwdFn.addListener(_save);
    _timeoutFn.addListener(_save);
  }

  VpsConfig _buildConfig() {
    return VpsConfig(
      enabled: _enabled,
      host: _hostCtl.text.trim(),
      port: int.tryParse(_portCtl.text.trim()) ?? 22,
      username: _userCtl.text.trim(),
      password: _passCtl.text,
      defaultCwd: _cwdCtl.text.trim().isNotEmpty
          ? _cwdCtl.text.trim()
          : '/root',
      timeoutSeconds: int.tryParse(_timeoutCtl.text.trim()) ?? 12,
    );
  }

  void _save() {
    final sp = context.read<SettingsProvider>();
    sp.setVpsConfig(_buildConfig());
  }

  void _applyBoxedPreset() {
    setState(() {
      _hostCtl.text = 'ssh.boxd.sh';
      _portCtl.text = '22';
      _userCtl.text = 'root';
      _cwdCtl.text = '/root';
      _timeoutCtl.text = '30';
    });
    _save();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Boxed.sh microVM template applied. Enter your machine ID / token.',
        ),
      ),
    );
  }

  void _applyLocalDockerPreset() {
    setState(() {
      _hostCtl.text = '127.0.0.1';
      _portCtl.text = '2222';
      _userCtl.text = 'root';
      _cwdCtl.text = '/workspace';
      _timeoutCtl.text = '15';
    });
    _save();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Local Docker container sandbox template applied.'),
      ),
    );
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    _cwdCtl.dispose();
    _timeoutCtl.dispose();
    _testCmdCtl.dispose();
    _hostFn.dispose();
    _portFn.dispose();
    _userFn.dispose();
    _passFn.dispose();
    _cwdFn.dispose();
    _timeoutFn.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    _save();
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
      _connectionError = null;
      _connectionInfo = null;
    });

    final cfg = _buildConfig();
    final res = await SandboxVpsService.instance.testConnection(cfg);

    if (!mounted) return;
    setState(() {
      _testingConnection = false;
      _connectionOk = res['ok'] == true;
      _latencyMs = res['latencyMs'] as int?;
      if (_connectionOk == true) {
        _connectionInfo = res['info']?.toString();
      } else {
        _connectionError = res['error']?.toString();
      }
    });
  }

  Future<void> _runTestCommand() async {
    final cmd = _testCmdCtl.text.trim();
    if (cmd.isEmpty) return;
    _save();

    setState(() {
      _runningCommand = true;
      _cmdResult = null;
    });

    final cfg = _buildConfig();
    final res = await SandboxVpsService.instance.executeCommand(
      config: cfg,
      command: cmd,
    );

    if (!mounted) return;
    setState(() {
      _runningCommand = false;
      _cmdResult = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsPageSandboxVps),
        leading: Navigator.canPop(context)
            ? IosIconButton(
                icon: Lucide.ArrowLeft,
                onTap: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Banner Card
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF161B22), const Color(0xFF0D1117)]
                    : [const Color(0xFFF0F4F8), const Color(0xFFE2E8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF30363D)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Lucide.Server,
                    size: 20,
                    color: Color(0xFF58A6FF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autonomous Sandbox VPS',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allows VOID to execute shell commands, run Python/Bash scripts, compile code, inspect servers, and manipulate files directly in your remote Linux sandbox.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sandbox Presets & Boxed.sh microVMs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Lucide.Box, size: 14),
                  label: const Text(
                    'Boxed.sh microVM',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: _applyBoxedPreset,
                ),
                ActionChip(
                  avatar: const Icon(Lucide.Server, size: 14),
                  label: const Text(
                    'Local Docker',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: _applyLocalDockerPreset,
                ),
                ActionChip(
                  avatar: const Icon(Lucide.Terminal, size: 14),
                  label: const Text(
                    'External MCP Sandbox',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => const McpPage()));
                  },
                ),
              ],
            ),
          ),

          // Main Configuration Form
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Enable VPS Execution',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                    IosSwitch(
                      value: _enabled,
                      onChanged: (v) {
                        setState(() => _enabled = v);
                        _save();
                      },
                    ),
                  ],
                ),
              ),
              _buildField(
                label: 'Server Host / IP',
                child: TextField(
                  controller: _hostCtl,
                  focusNode: _hostFn,
                  decoration: _inputDecoration(context, hint: '103.30.211.131'),
                ),
              ),
              _buildField(
                label: 'SSH Port',
                child: TextField(
                  controller: _portCtl,
                  focusNode: _portFn,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(context, hint: '22'),
                ),
              ),
              _buildField(
                label: 'Username',
                child: TextField(
                  controller: _userCtl,
                  focusNode: _userFn,
                  decoration: _inputDecoration(context, hint: 'root'),
                ),
              ),
              _buildField(
                label: 'Password',
                child: TextField(
                  controller: _passCtl,
                  focusNode: _passFn,
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration(
                    context,
                    hint: 'SSH password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Lucide.Eye : Lucide.EyeOff,
                        size: 16,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ),
              _buildField(
                label: 'Default Working Directory',
                child: TextField(
                  controller: _cwdCtl,
                  focusNode: _cwdFn,
                  decoration: _inputDecoration(context, hint: '/root'),
                ),
              ),
              _buildField(
                label: 'Timeout (Seconds)',
                child: TextField(
                  controller: _timeoutCtl,
                  focusNode: _timeoutFn,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(context, hint: '12'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Test SSH Connection Card
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Lucide.Activity,
                          size: 16,
                          color: Color(0xFF58A6FF),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connection Diagnostics',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _testingConnection
                              ? null
                              : _testConnection,
                          icon: _testingConnection
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Lucide.Zap, size: 14),
                          label: Text(
                            _testingConnection ? 'Testing...' : 'Test SSH',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_connectionOk == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.appColors.success.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.appColors.success.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Lucide.CheckCircle,
                                  size: 15,
                                  color: context.appColors.success,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Connected Successfully (${_latencyMs ?? 0}ms latency)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: AppFontWeights.emphasis,
                                    color: context.appColors.success,
                                  ),
                                ),
                              ],
                            ),
                            if (_connectionInfo != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _connectionInfo!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_connectionOk == false) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Lucide.CircleAlert, size: 15, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Connection Failed: ${_connectionError ?? "Unknown error"}',
                                style: TextStyle(fontSize: 12, color: cs.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Interactive Command Execution Tester
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Lucide.Terminal,
                          size: 16,
                          color: Color(0xFF58A6FF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Test Command Execution',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _testCmdCtl,
                            decoration: _inputDecoration(
                              context,
                              hint: 'e.g. uname -a, free -h, uptime',
                            ),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _runningCommand ? null : _runTestCommand,
                          icon: _runningCommand
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Lucide.Play, size: 14),
                          label: Text(
                            _runningCommand ? 'Running' : 'Run',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_cmdResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0D1117)
                              : const Color(0xFFF6F8FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF30363D)
                                : const Color(0xFFD0D7DE),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Exit Code: ${_cmdResult!.exitCode}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: AppFontWeights.emphasis,
                                    color: _cmdResult!.exitCode == 0
                                        ? context.appColors.success
                                        : cs.error,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_cmdResult!.durationMs}ms',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (_cmdResult!.stdout.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                _cmdResult!.stdout.trimRight(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: isDark
                                      ? const Color(0xFFC9D1D9)
                                      : const Color(0xFF24292F),
                                ),
                              ),
                            ],
                            if (_cmdResult!.stderr.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                _cmdResult!.stderr.trimRight(),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: Color(0xFFF85149),
                                ),
                              ),
                            ],
                            if (_cmdResult!.error != null) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                _cmdResult!.error!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: Color(0xFFF85149),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: AppFontWeights.medium),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    String? hint,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF58A6FF)),
      ),
    );
  }
}
