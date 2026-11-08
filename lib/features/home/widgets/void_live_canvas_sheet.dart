import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';

class VoidLiveCanvasSheet extends StatefulWidget {
  const VoidLiveCanvasSheet({
    super.key,
    this.initialHtml,
    this.onAskAiToIterate,
  });

  final String? initialHtml;
  final ValueChanged<String>? onAskAiToIterate;

  /// Extracts the latest HTML or SVG code block from markdown text if present.
  static String? extractHtmlFromMarkdown(String? markdown) {
    if (markdown == null || markdown.trim().isEmpty) return null;
    final htmlFence = RegExp(
      r'```(?:html|svg|htm)\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final matches = htmlFence.allMatches(markdown).toList();
    if (matches.isNotEmpty) {
      return matches.last.group(1)?.trim();
    }
    if (markdown.contains('<!DOCTYPE html>') || markdown.contains('<html')) {
      return markdown;
    }
    return null;
  }

  static Future<void> show(
    BuildContext context, {
    String? latestAssistantMarkdown,
    ValueChanged<String>? onAskAiToIterate,
  }) {
    final extracted = extractHtmlFromMarkdown(latestAssistantMarkdown);
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
            child: VoidLiveCanvasSheet(
              initialHtml: extracted,
              onAskAiToIterate: onAskAiToIterate,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: VoidLiveCanvasSheet(
          initialHtml: extracted,
          onAskAiToIterate: onAskAiToIterate,
        ),
      ),
    );
  }

  @override
  State<VoidLiveCanvasSheet> createState() => _VoidLiveCanvasSheetState();
}

class _VoidLiveCanvasSheetState extends State<VoidLiveCanvasSheet> {
  late final TextEditingController _codeCtrl;
  InAppWebViewController? _webCtrl;
  bool _showCode = false;

  static const String _defaultStarterHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body {
    margin: 0;
    background: #0a0a0e;
    color: #f4f4f5;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    overflow: hidden;
  }
  .card {
    background: rgba(24, 24, 30, 0.85);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 22px;
    padding: 28px;
    max-width: 420px;
    text-align: center;
    box-shadow: 0 20px 50px rgba(0,0,0,0.6);
  }
  h2 { margin: 0 0 8px; font-size: 22px; letter-spacing: -0.4px; }
  p { margin: 0 0 18px; font-size: 13.5px; color: #a1a1aa; line-height: 1.5; }
  button {
    background: #ffffff;
    color: #09090b;
    border: none;
    border-radius: 12px;
    padding: 10px 20px;
    font-weight: 600;
    cursor: pointer;
    transition: transform 0.15s ease;
  }
  button:active { transform: scale(0.96); }
  #counter { font-size: 32px; font-weight: 700; margin: 12px 0; color: #38bdf8; }
</style>
</head>
<body>
  <div class="card">
    <h2>VOID Live UI Sandbox</h2>
    <p>Ask VOID to build any HTML/CSS/JS app, interactive chart, or game in chat, or edit code directly in the Source tab.</p>
    <div id="counter">0</div>
    <button onclick="document.getElementById('counter').innerText = parseInt(document.getElementById('counter').innerText) + 1">
      Trigger Interactive Event
    </button>
  </div>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text: widget.initialHtml ?? _defaultStarterHtml,
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _reloadPreview() {
    Haptics.light();
    setState(() => _showCode = false);
    _webCtrl?.loadData(
      data: _codeCtrl.text,
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  bool get _supportsInlineWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: isDesktop
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF27272A)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: Row(
                children: [
                  const VoidLogo(size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOID Live Code & UI Canvas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Interactive HTML / JS / SVG Sandbox',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Lucide.Eye, size: 14),
                        label: Text('Preview', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Lucide.Code, size: 14),
                        label: Text('Source', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_showCode},
                    onSelectionChanged: (s) {
                      Haptics.light();
                      final next = s.first;
                      setState(() => _showCode = next);
                      if (!next) {
                        _reloadPreview();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Lucide.X, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),

            // Body
            Expanded(
              child: _showCode
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _codeCtrl,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          color: cs.onSurface,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF101014)
                              : cs.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    )
                  : _supportsInlineWebView
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InAppWebView(
                          initialData: InAppWebViewInitialData(
                            data: _codeCtrl.text,
                            mimeType: 'text/html',
                            encoding: 'utf-8',
                          ),
                          onWebViewCreated: (ctrl) => _webCtrl = ctrl,
                        ),
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Switch to Source tab to edit or copy HTML/JS artifact.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
            ),

            // Footer toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  IosTextButton(
                    label: 'Run / Reload',
                    icon: Lucide.RefreshCw,
                    fontSize: 12,
                    onPressed: _reloadPreview,
                  ),
                  const SizedBox(width: 8),
                  IosTextButton(
                    label: 'Copy Code',
                    icon: Lucide.Copy,
                    fontSize: 12,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _codeCtrl.text));
                      showAppSnackBar(
                        context,
                        message: 'Canvas code copied to clipboard',
                        type: NotificationType.success,
                      );
                    },
                  ),
                  const Spacer(),
                  if (widget.onAskAiToIterate != null)
                    IosTextButton(
                      label: 'Ask VOID to Build UI',
                      icon: Lucide.Sparkles,
                      fontSize: 12,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onAskAiToIterate!(
                          'Create a complete, self-contained interactive single-file HTML/CSS/JS web app inside an ```html code block with modern dark/light responsive styling for: ',
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
