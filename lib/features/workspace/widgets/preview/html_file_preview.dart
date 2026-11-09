import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/segmented_tabs.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

import 'code_file_preview.dart';
import 'preview_actions.dart';
import 'preview_states.dart';

class HtmlFilePreview extends StatefulWidget {
  const HtmlFilePreview({super.key, required this.file, this.autoLoad = true});

  final File file;
  final bool autoLoad;

  @override
  State<HtmlFilePreview> createState() => _HtmlFilePreviewState();
}

class _HtmlFilePreviewState extends State<HtmlFilePreview> {
  Uri? _serverUri;
  InAppWebViewController? _webCtrl;
  Object? _error;
  bool _showSource = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      unawaited(_init());
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(HtmlFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      unawaited(_init());
    }
  }

  @override
  void dispose() {
    unawaited(closePreviewFileBrowserServer());
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = await startPreviewFileBrowserServer(widget.file);
      if (!mounted) return;
      setState(() {
        _serverUri = uri;
        _loading = false;
        _error = null;
      });
      _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SegmentedTabs(
                  tabs: [
                    SegmentedTab(
                      label: l10n.workspacePreviewSource,
                      icon: Lucide.FileCode,
                    ),
                    SegmentedTab(
                      label: l10n.workspacePreviewRendered,
                      icon: Lucide.Eye,
                    ),
                  ],
                  index: _showSource ? 0 : 1,
                  onChanged: (next) => setState(() => _showSource = next == 0),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: l10n.workspacePreviewOpenWith,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => openPreviewFileInBrowser(context, widget.file),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Lucide.ExternalLink,
                          size: 14,
                          color: cs.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Browser',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_showSource) {
      return CodeFilePreview(
        file: widget.file,
        autoLoad: widget.autoLoad,
        language: 'xml',
      );
    }
    if (_error != null) {
      return PreviewError(onRetry: () => unawaited(_init()));
    }
    if (_loading || _serverUri == null) {
      return const PreviewLoading();
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(_serverUri!)),
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        transparentBackground: false,
      ),
      onWebViewCreated: (c) => _webCtrl = c,
    );
  }
}
