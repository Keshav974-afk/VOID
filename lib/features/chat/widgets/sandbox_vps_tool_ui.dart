import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/sandbox_vps/sandbox_vps_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Interactive Terminal Card for Sandbox VPS / SSH Execution.
class SandboxVpsToolUi extends StatefulWidget {
  const SandboxVpsToolUi({super.key, required this.result, this.textColor});

  final SandboxVpsToolResult result;
  final Color? textColor;

  @override
  State<SandboxVpsToolUi> createState() => _SandboxVpsToolUiState();
}

class _SandboxVpsToolUiState extends State<SandboxVpsToolUi> {
  bool _expanded = true;
  bool _copied = false;

  void _copyOutput() {
    final text = widget.result.stdout.isNotEmpty
        ? widget.result.stdout
        : widget.result.stderr.isNotEmpty
        ? widget.result.stderr
        : widget.result.error ?? '';
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = widget.result;
    final isSuccess = res.status == 'success' && res.exitCode == 0;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : const Color(0xFFD0D7DE);
    final codeBg = isDark ? const Color(0xFF161B22) : const Color(0xFFEAEEF2);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFF0F3F6),
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                Icon(
                  Lucide.Terminal,
                  size: 15,
                  color: isSuccess
                      ? const Color(0xFF2EA043)
                      : const Color(0xFFF85149),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    res.host.isNotEmpty ? 'vps: ${res.host}' : 'sandbox-vps',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Exit code badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isSuccess
                                ? const Color(0xFF2EA043)
                                : const Color(0xFFDA3633))
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSuccess
                          ? const Color(0xFF2EA043)
                          : const Color(0xFFDA3633),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isSuccess ? 'exit 0' : 'exit ${res.exitCode}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: AppFontWeights.emphasis,
                      color: isSuccess
                          ? const Color(0xFF3FB950)
                          : const Color(0xFFF85149),
                    ),
                  ),
                ),
                if (res.durationMs > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${res.durationMs}ms',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Copy button
                InkWell(
                  onTap: _copyOutput,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Lucide.Check : Lucide.Copy,
                          size: 12,
                          color: _copied ? const Color(0xFF3FB950) : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied ? const Color(0xFF3FB950) : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Expand / Collapse toggle
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Command prompt preview (always shown)
          if (res.command != null && res.command!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: codeBg.withValues(alpha: 0.5),
              child: SelectableText(
                '\$ ${res.command}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: AppFontWeights.emphasis,
                  color: const Color(0xFF58A6FF),
                ),
              ),
            ),

          // Expanded Output Body
          if (_expanded) ...[
            if (res.action == 'status' && res.systemInfo != null)
              _buildSystemInfo(res.systemInfo!, isDark),
            if (res.action == 'list_dir' && res.entries.isNotEmpty)
              _buildDirectoryEntries(res.entries, isDark),
            if (res.stdout.isNotEmpty)
              _buildConsoleBlock(
                title: 'STDOUT',
                content: res.stdout,
                color: isDark
                    ? const Color(0xFFC9D1D9)
                    : const Color(0xFF24292F),
                codeBg: codeBg,
              ),
            if (res.stderr.isNotEmpty)
              _buildConsoleBlock(
                title: 'STDERR',
                content: res.stderr,
                color: const Color(0xFFF85149),
                codeBg: codeBg,
              ),
            if (res.error != null && res.error!.isNotEmpty)
              _buildConsoleBlock(
                title: 'ERROR',
                content: res.error!,
                color: const Color(0xFFF85149),
                codeBg: codeBg,
              ),
            if (res.stdout.isEmpty &&
                res.stderr.isEmpty &&
                res.error == null &&
                (res.action != 'status' && res.action != 'list_dir'))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '(Command completed with no terminal output)',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsoleBlock({
    required String title,
    required String content,
    required Color color,
    required Color codeBg,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: codeBg,
      child: SelectableText(
        content.trimRight(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.4,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSystemInfo(Map<String, dynamic> info, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: info.entries.map((e) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF21262D) : const Color(0xFFE1E4E8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${e.key}: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: AppFontWeights.emphasis,
                  ),
                ),
                Text(
                  '${e.value}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDirectoryEntries(List<String> entries, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final item = entries[index];
          final isDir = item.endsWith('/');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  isDir ? Lucide.Folder : Lucide.File,
                  size: 13,
                  color: isDir ? const Color(0xFF58A6FF) : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: isDir ? const Color(0xFF58A6FF) : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
