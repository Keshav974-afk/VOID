import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../browser/browser_navigation.dart';

/// Information parsed from a Cloud Computer / Simular Box / Sandbox session.
class CloudComputerLiveSessionInfo {
  const CloudComputerLiveSessionInfo({
    required this.liveUrl,
    this.boxId,
    this.desktopImagePath,
    this.host,
    this.serviceName = 'Simular Box',
    this.isSimular = true,
  });

  final String liveUrl;
  final String? boxId;
  final String? desktopImagePath;
  final String? host;
  final String serviceName;
  final bool isSimular;

  /// Detects whether text, tool calls, or content describe an active cloud computer / sandbox session.
  static CloudComputerLiveSessionInfo? detect(
    String? content, {
    String? toolName,
    Map<String, dynamic>? toolArgs,
    String? toolContent,
  }) {
    final combined = StringBuffer();
    if (content != null) combined.writeln(content);
    if (toolContent != null) combined.writeln(toolContent);
    if (toolArgs != null) combined.writeln(toolArgs.toString());

    final fullText = combined.toString();
    if (fullText.isEmpty && (toolName == null || !toolName.contains('box'))) {
      return null;
    }

    // 1. Check for Simular Box URLs: https://box.simular.ai/box/<id>/live
    final simularRegex = RegExp(
      r'https?://box\.simular\.ai/box/([a-zA-Z0-9_\-]+)(?:/live)?',
      caseSensitive: false,
    );
    final simularMatch = simularRegex.firstMatch(fullText);
    if (simularMatch != null) {
      final id = simularMatch.group(1)!;
      final liveUrl = 'https://box.simular.ai/box/$id/live';
      final img = _detectDesktopImage(fullText);
      return CloudComputerLiveSessionInfo(
        liveUrl: liveUrl,
        boxId: id,
        desktopImagePath: img,
        serviceName: 'Simular Box',
        isSimular: true,
      );
    }

    // 2. Check for boxd.sh URLs
    final boxdRegex = RegExp(
      r'https?://([a-zA-Z0-9_\-]+\.)?boxd\.sh(?:/[^\s)"]*)?',
      caseSensitive: false,
    );
    final boxdMatch = boxdRegex.firstMatch(fullText);
    if (boxdMatch != null) {
      final liveUrl = boxdMatch.group(0)!;
      final img = _detectDesktopImage(fullText);
      return CloudComputerLiveSessionInfo(
        liveUrl: liveUrl,
        desktopImagePath: img,
        serviceName: 'Boxd Sandbox',
        isSimular: false,
      );
    }

    // 3. Check for explicit box_* tool calls or box_id in args
    if (toolName != null &&
        (toolName.toLowerCase().startsWith('box_') ||
            toolName.toLowerCase().contains('box_mcp') ||
            toolName.toLowerCase() == 'box')) {
      String? id;
      if (toolArgs != null && toolArgs.containsKey('box_id')) {
        id = toolArgs['box_id']?.toString();
      } else {
        final idMatch = RegExp(
          r'cb-[a-zA-Z0-9_\-]+',
          caseSensitive: false,
        ).firstMatch(fullText);
        id = idMatch?.group(0);
      }
      if (id != null && id.isNotEmpty) {
        final liveUrl = 'https://box.simular.ai/box/$id/live';
        final img = _detectDesktopImage(fullText);
        return CloudComputerLiveSessionInfo(
          liveUrl: liveUrl,
          boxId: id,
          desktopImagePath: img,
          serviceName: 'Simular Box',
          isSimular: true,
        );
      }
    }

    // 4. Check for generic VNC/remote desktop web viewers (noVNC / web desktop)
    final vncRegex = RegExp(
      r'https?://[^\s)"]+:(?:5900|5901|6080|8080)/[^\s)"]*(?:vnc|desktop|live)[^\s)"]*',
      caseSensitive: false,
    );
    final vncMatch = vncRegex.firstMatch(fullText);
    if (vncMatch != null) {
      final liveUrl = vncMatch.group(0)!;
      final img = _detectDesktopImage(fullText);
      return CloudComputerLiveSessionInfo(
        liveUrl: liveUrl,
        desktopImagePath: img,
        serviceName: 'Cloud Desktop',
        isSimular: false,
      );
    }

    return null;
  }

  static String? _detectDesktopImage(String text) {
    // Look for image references like box_desktop.png, desktop.png, screenshot.png
    final imgRegex = RegExp(
      r'([^\s)"]+?(?:box_desktop|desktop|screenshot|screen)[^\s)"]*?\.(?:png|jpg|jpeg|webp))',
      caseSensitive: false,
    );
    final match = imgRegex.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }
}

/// Interactive Card for Cloud Computer / Simular Box Live Sessions.
/// Renders a live monitoring viewport, status indicators, and a prominent
/// "Take Control" action to interact with the remote desktop directly.
class CloudComputerLiveCard extends StatefulWidget {
  const CloudComputerLiveCard({
    super.key,
    required this.sessionInfo,
    this.conversationId,
  });

  final CloudComputerLiveSessionInfo sessionInfo;
  final String? conversationId;

  @override
  State<CloudComputerLiveCard> createState() => _CloudComputerLiveCardState();
}

class _CloudComputerLiveCardState extends State<CloudComputerLiveCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  bool _isHovering = false;
  bool _copied = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkImageFile();
  }

  @override
  void didUpdateWidget(covariant CloudComputerLiveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionInfo.desktopImagePath !=
        widget.sessionInfo.desktopImagePath) {
      _checkImageFile();
    }
  }

  void _checkImageFile() {
    final rawPath = widget.sessionInfo.desktopImagePath;
    if (rawPath != null && rawPath.isNotEmpty) {
      final fixed = SandboxPathResolver.fix(rawPath);
      final f = File(fixed);
      if (f.existsSync()) {
        setState(() => _imageFile = f);
        return;
      }
      // Check current working directory
      final localF = File(rawPath);
      if (localF.existsSync()) {
        setState(() => _imageFile = localF);
        return;
      }
    }
    setState(() => _imageFile = null);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _takeControl() async {
    HapticFeedback.mediumImpact();
    await openBrowserPage(
      context,
      url: widget.sessionInfo.liveUrl,
      conversationId: widget.conversationId,
      fullPage: true,
    );
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.sessionInfo.liveUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.sessionInfo.liveUrl));
    setState(() => _copied = true);
    HapticFeedback.selectionClick();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : const Color(0xFFD0D7DE);
    final headerBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF0F3F6);

    final info = widget.sessionInfo;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header Bar ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                // Live Pulsing Dot
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, _) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFF22C55E,
                      ).withValues(alpha: _pulseAnim.value),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF22C55E,
                          ).withValues(alpha: _pulseAnim.value * 0.7),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: AppFontWeights.emphasis,
                    color: const Color(0xFF22C55E),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 10),
                // Icon & Title
                Icon(
                  Lucide.Monitor,
                  size: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    info.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.emphasis,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (info.boxId != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF21262D)
                          : const Color(0xFFE1E4E8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      info.boxId!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Primary "Take Control" Button
                _TakeControlButton(onTap: _takeControl),
              ],
            ),
          ),

          // ── Screen Viewport ──────────────────────────────────────────
          GestureDetector(
            onTap: _takeControl,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              cursor: SystemMouseCursors.click,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      minHeight: 180,
                      maxHeight: 340,
                    ),
                    color: isDark
                        ? const Color(0xFF030712)
                        : const Color(0xFF1E293B),
                    alignment: Alignment.center,
                    child: _imageFile != null
                        ? Image.file(
                            _imageFile!,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          )
                        : _buildEmptyViewport(isDark),
                  ),

                  // Overlay Badge / Hover Button
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _isHovering ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(
                                alpha: _isHovering ? 0.65 : 0.35,
                              ),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        alignment: Alignment.bottomCenter,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Lucide.MousePointerClick,
                                    size: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isHovering
                                        ? 'Click to Take Control'
                                        : 'Agent Driving · Tap to Take Control',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
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
          ),

          // ── Footer Toolbar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(top: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                // Quick info chip
                Icon(
                  Lucide.Cpu,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  'Ubuntu · Chrome GUI Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                // Copy link button
                _FooterIconButton(
                  icon: _copied ? Lucide.Check : Lucide.Copy,
                  label: _copied ? 'Copied' : 'Copy Link',
                  color: _copied ? const Color(0xFF22C55E) : null,
                  onTap: _copyLink,
                ),
                const SizedBox(width: 8),
                // External browser button
                _FooterIconButton(
                  icon: Lucide.ExternalLink,
                  label: 'Popout',
                  onTap: _openExternal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyViewport(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Lucide.Monitor, size: 24, color: Color(0xFF22C55E)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cloud Computer Stream Active',
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.emphasis,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.sessionInfo.boxId != null
                ? 'Session ${widget.sessionInfo.boxId}'
                : 'Interactive session ready',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _TakeControlButton extends StatefulWidget {
  const _TakeControlButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TakeControlButton> createState() => _TakeControlButtonState();
}

class _TakeControlButtonState extends State<_TakeControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      label: 'Take Control',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.MousePointerClick, size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text(
                  'Take Control',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: c,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
