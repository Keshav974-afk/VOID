import 'package:flutter/material.dart';

import '../../../core/services/desktop_control/desktop_control_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';
import '../../settings/pages/void_knowledge_vault_page.dart';
import '../../settings/pages/void_macros_page.dart';
import 'void_council_sheet.dart';
import 'void_live_canvas_sheet.dart';
import 'void_live_voice_sheet.dart';

class VoidPowerHubSheet extends StatelessWidget {
  const VoidPowerHubSheet({
    super.key,
    required this.onDispatchPrompt,
    required this.onInsertComposerText,
    this.latestAssistantMarkdown,
    this.recentUserPrompts = const [],
  });

  final ValueChanged<String> onDispatchPrompt;
  final ValueChanged<String> onInsertComposerText;
  final String? latestAssistantMarkdown;
  final List<String> recentUserPrompts;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onDispatchPrompt,
    required ValueChanged<String> onInsertComposerText,
    String? latestAssistantMarkdown,
    List<String> recentUserPrompts = const [],
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: VoidPowerHubSheet(
              onDispatchPrompt: onDispatchPrompt,
              onInsertComposerText: onInsertComposerText,
              latestAssistantMarkdown: latestAssistantMarkdown,
              recentUserPrompts: recentUserPrompts,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoidPowerHubSheet(
        onDispatchPrompt: onDispatchPrompt,
        onInsertComposerText: onInsertComposerText,
        latestAssistantMarkdown: latestAssistantMarkdown,
        recentUserPrompts: recentUserPrompts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    final items =
        <
          ({
            IconData icon,
            String title,
            String subtitle,
            Color accent,
            VoidCallback onTap,
          })
        >[
          (
            icon: Lucide.AudioLines,
            title: 'Live Duplex Voice',
            subtitle: 'Hands-free real-time voice conversation with barge-in',
            accent: const Color(0xFF38BDF8),
            onTap: () {
              Navigator.of(context).pop();
              VoidLiveVoiceSheet.show(
                context,
                onSendSpokenPrompt: onDispatchPrompt,
              );
            },
          ),
          (
            icon: Lucide.Users,
            title: 'Multi-Agent Council',
            subtitle:
                'Architect, Implementer & Red-Team Auditor debate & synthesize',
            accent: const Color(0xFFA855F7),
            onTap: () {
              Navigator.of(context).pop();
              VoidCouncilSheet.show(
                context,
                onLaunchCouncilPrompt: onDispatchPrompt,
              );
            },
          ),
          (
            icon: Lucide.Workflow,
            title: 'Agent Macros & Recipes',
            subtitle: 'Record & replay multi-step autonomous agent workflows',
            accent: const Color(0xFFF59E0B),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoidMacrosPage(
                    onRunMacro: onDispatchPrompt,
                    recentUserPrompts: recentUserPrompts,
                  ),
                ),
              );
            },
          ),
          (
            icon: Lucide.LayoutPanelLeft,
            title: 'Live Code & UI Canvas',
            subtitle: 'Interactive HTML / CSS / JS / SVG sandbox previewer',
            accent: const Color(0xFF10B981),
            onTap: () {
              Navigator.of(context).pop();
              VoidLiveCanvasSheet.show(
                context,
                latestAssistantMarkdown: latestAssistantMarkdown,
                onAskAiToIterate: onInsertComposerText,
              );
            },
          ),
          (
            icon: Lucide.ScanEye,
            title: 'Universal Screen Context',
            subtitle: DesktopControlService.isDesktopPlatform
                ? 'Snap active desktop window/screen and analyze immediately'
                : 'Inspect current screen content and assist immediately',
            accent: const Color(0xFFEC4899),
            onTap: () {
              Navigator.of(context).pop();
              final screenPrompt = DesktopControlService.isDesktopPlatform
                  ? 'Capture and inspect my current desktop screen / active window using desktop_control, read all visible content or errors, and tell me what is on screen and how you can help.'
                  : 'Inspect my current screen using phone_control (or screen context), read the visible UI elements and text, and summarize or assist with what is on screen.';
              onDispatchPrompt(screenPrompt);
            },
          ),
          (
            icon: Lucide.Database,
            title: 'Local Knowledge Vault (RAG)',
            subtitle: 'Index local files & notes for grounded, cited answers',
            accent: const Color(0xFF6366F1),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoidKnowledgeVaultPage(
                    onInsertContext: onInsertComposerText,
                  ),
                ),
              );
            },
          ),
        ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: isDesktop
            ? BorderRadius.circular(26)
            : const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF27272A)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDesktop)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Row(
                children: [
                  const VoidLogo(size: 24, glow: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOID Intelligence Hub',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Next-generation autonomous agent capabilities',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Lucide.X, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Haptics.light();
                      item.onTap();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF18181B)
                            : cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: item.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              item.icon,
                              size: 19,
                              color: item.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: AppFontWeights.emphasis,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Lucide.ChevronRight,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
