import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/desktop_control/desktop_control_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../../utils/app_directories.dart';
import '../../browser/browser_navigation.dart';
import '../../chat/widgets/tools_sheet_row.dart';
import '../../settings/pages/void_knowledge_vault_page.dart';
import '../../settings/pages/void_macros_page.dart';
import 'void_council_sheet.dart';
import 'void_live_voice_sheet.dart';

class VoidPowerHubSheet extends StatelessWidget {
  const VoidPowerHubSheet({
    super.key,
    required this.onDispatchPrompt,
    required this.onInsertComposerText,
    this.latestAssistantMarkdown,
    this.recentUserPrompts = const [],
    this.conversationId,
  });

  final ValueChanged<String> onDispatchPrompt;
  final ValueChanged<String> onInsertComposerText;
  final String? latestAssistantMarkdown;
  final List<String> recentUserPrompts;
  final String? conversationId;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onDispatchPrompt,
    required ValueChanged<String> onInsertComposerText,
    String? latestAssistantMarkdown,
    List<String> recentUserPrompts = const [],
    String? conversationId,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: VoidPowerHubSheet(
              onDispatchPrompt: onDispatchPrompt,
              onInsertComposerText: onInsertComposerText,
              latestAssistantMarkdown: latestAssistantMarkdown,
              recentUserPrompts: recentUserPrompts,
              conversationId: conversationId,
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
        conversationId: conversationId,
      ),
    );
  }

  Future<void> _openWebArtifactLocally(BuildContext context) async {
    Navigator.of(context).pop();

    String? htmlContent;
    if (latestAssistantMarkdown != null &&
        latestAssistantMarkdown!.trim().isNotEmpty) {
      final htmlFence = RegExp(
        r'```(?:html|svg|htm)\s*([\s\S]*?)```',
        caseSensitive: false,
      );
      final matches = htmlFence.allMatches(latestAssistantMarkdown!).toList();
      if (matches.isNotEmpty) {
        htmlContent = matches.last.group(1)?.trim();
      } else if (latestAssistantMarkdown!.contains('<!DOCTYPE html>') ||
          latestAssistantMarkdown!.contains('<html')) {
        htmlContent = latestAssistantMarkdown;
      }
    }

    htmlContent ??= '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VOID Web Preview</title>
  <style>
    body {
      margin: 0;
      padding: 40px 24px;
      background: #09090b;
      color: #f4f4f5;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 80vh;
      text-align: center;
    }
    .card {
      background: #18181b;
      border: 1px solid #27272a;
      border-radius: 18px;
      padding: 32px 24px;
      max-width: 480px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    }
    h1 { margin: 0 0 12px; font-size: 20px; font-weight: 600; }
    p { margin: 0 0 16px; font-size: 13.5px; color: #a1a1aa; line-height: 1.5; }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      font-size: 11px;
      font-weight: 600;
      color: #38bdf8;
      background: rgba(56, 189, 248, 0.12);
      border-radius: 8px;
      margin-bottom: 14px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">In-App Browser</div>
    <h1>VOID Local Web Viewer</h1>
    <p>Ask VOID in chat to build a website, interactive dashboard, or HTML/JS web application. Its live artifact will render right here in your local browser.</p>
  </div>
</body>
</html>''';

    final cacheDir = await AppDirectories.getCacheDirectory();
    final file = File(p.join(cacheDir.path, 'artifact_preview.html'));
    await file.writeAsString(htmlContent);

    if (context.mounted) {
      await openBrowserPage(
        context,
        conversationId: conversationId,
        url: file.uri.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final bg = context.overlaySurface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: isDesktop
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              Row(
                children: [
                  const VoidLogo(size: 22, glow: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOID Studio',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Autonomous agent tools & multi-agent workflows',
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
              const SizedBox(height: 14),

              // Multi-Agent & Workflows
              SectionCard(
                children: [
                  ToolsSheetRow(
                    icon: Lucide.Users,
                    label: 'Multi-Agent Council',
                    subtitle:
                        'Multi-model deliberation, red-team audit & synthesis',
                    onTap: () {
                      Navigator.of(context).pop();
                      VoidCouncilSheet.show(
                        context,
                        onLaunchCouncilPrompt: onDispatchPrompt,
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  ToolsSheetRow(
                    icon: Lucide.Workflow,
                    label: 'Agent Macros & Recipes',
                    subtitle: 'Autonomous multi-step record & replay workflows',
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
                ],
              ),
              const SizedBox(height: 10),

              // Native Environments & Interactive Tools
              SectionCard(
                children: [
                  ToolsSheetRow(
                    icon: Lucide.Globe,
                    label: 'In-App Browser & Web Artifacts',
                    subtitle:
                        'Open live HTML/JS artifacts & websites in app browser',
                    onTap: () => _openWebArtifactLocally(context),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  ToolsSheetRow(
                    icon: Lucide.AudioLines,
                    label: 'Live Duplex Voice',
                    subtitle: 'Real-time voice assistant with barge-in support',
                    onTap: () {
                      Navigator.of(context).pop();
                      VoidLiveVoiceSheet.show(
                        context,
                        onSendSpokenPrompt: onDispatchPrompt,
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  ToolsSheetRow(
                    icon: Lucide.ScanEye,
                    label: 'Screen Context Analysis',
                    subtitle: DesktopControlService.isDesktopPlatform
                        ? 'Snap active desktop screen/window and analyze'
                        : 'Inspect current mobile viewport and assist',
                    onTap: () {
                      Navigator.of(context).pop();
                      final screenPrompt =
                          DesktopControlService.isDesktopPlatform
                          ? 'Capture and inspect my current desktop screen / active window using desktop_control, read all visible content or errors, and tell me what is on screen and how you can help.'
                          : 'Inspect my current screen using phone_control (or screen context), read the visible UI elements and text, and summarize or assist with what is on screen.';
                      onDispatchPrompt(screenPrompt);
                    },
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  ToolsSheetRow(
                    icon: Lucide.Database,
                    label: 'Knowledge Vault (Local RAG)',
                    subtitle: 'Search and cite your private local documents',
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
