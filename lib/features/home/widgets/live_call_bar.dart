import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/asr/asr_service_options.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../features/settings/pages/tts_settings_page.dart';

/// Grok-style Live Call Bar with 2-way continuous voice conversational loop,
/// video camera input, speaker toggle, animated mic audio waveform dots,
/// quick text entry, and red hangup button.
class LiveCallBar extends StatefulWidget {
  const LiveCallBar({
    super.key,
    required this.onSend,
    required this.onHangup,
    required this.isLoading,
    this.latestAiResponse,
  });

  final Future<void> Function(String text, {List<String>? imagePaths}) onSend;
  final VoidCallback onHangup;
  final bool isLoading;
  final String? latestAiResponse;

  @override
  State<LiveCallBar> createState() => _LiveCallBarState();
}

class _LiveCallBarState extends State<LiveCallBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  bool _speakerEnabled = true;
  bool _isMuted = false;
  String _lastSpokenResponse = '';
  Timer? _speechPauseTimer;
  String _currentTranscript = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLiveListening();
    });
  }

  @override
  void didUpdateWidget(covariant LiveCallBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When AI finished loading and provided response, speak it if speaker is on
    if (oldWidget.isLoading && !widget.isLoading) {
      final response = widget.latestAiResponse;
      if (response != null &&
          response.trim().isNotEmpty &&
          response != _lastSpokenResponse) {
        _lastSpokenResponse = response;
        if (_speakerEnabled && mounted) {
          _speakAiResponse(response);
        } else {
          // If speaker disabled, resume listening immediately
          _startLiveListening();
        }
      }
    }
  }

  @override
  void dispose() {
    _speechPauseTimer?.cancel();
    _pulseController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _stopLiveListening();
    super.dispose();
  }

  Future<void> _startLiveListening() async {
    if (!mounted || _isMuted) return;
    final asr = context.read<AsrProvider>();
    final settings = context.read<SettingsProvider>();
    final selected = settings.selectedAsrService ??
        SystemAsrOptions(id: 'system_default', name: 'System');

    var recognizer = asr.canUse(selected) ? selected : null;
    if (recognizer == null) {
      final defaultSys = SystemAsrOptions(id: 'system_default', name: 'System');
      if (asr.canUse(defaultSys)) {
        recognizer = defaultSys;
      }
    }

    if (recognizer != null && !asr.isActive) {
      try {
        await asr.start(recognizer);
      } catch (_) {}
    }
  }

  Future<void> _stopLiveListening() async {
    final asr = context.read<AsrProvider>();
    if (asr.isActive) {
      try {
        await asr.cancel();
      } catch (_) {}
    }
  }

  Future<void> _speakAiResponse(String text) async {
    final tts = context.read<TtsProvider>();
    await _stopLiveListening();
    try {
      await tts.speak(text);
    } catch (_) {}

    // When TTS finishes speaking, automatically resume listening for user's next turn
    if (mounted && !_isMuted) {
      _startLiveListening();
    }
  }

  void _handleAsrUpdate(AsrProvider asr) {
    if (_isMuted || widget.isLoading) return;
    final text = asr.transcript.trim();
    if (text.isNotEmpty && text != _currentTranscript) {
      _currentTranscript = text;
      _speechPauseTimer?.cancel();
      // Auto-send after 1.4s of user silence
      _speechPauseTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || _currentTranscript.isEmpty) return;
        _commitUserSpeech(_currentTranscript);
      });
    }
  }

  Future<void> _commitUserSpeech(String text) async {
    _speechPauseTimer?.cancel();
    _currentTranscript = '';
    await _stopLiveListening();
    Haptics.light();
    await widget.onSend(text);
  }

  Future<void> _handleCameraCapture() async {
    Haptics.light();
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        await _stopLiveListening();
        await widget.onSend(
          'What do you see in this photo?',
          imagePaths: [file.path],
        );
      }
    } catch (_) {}
  }

  void _toggleSpeaker() {
    Haptics.light();
    setState(() {
      _speakerEnabled = !_speakerEnabled;
    });
    if (!_speakerEnabled) {
      context.read<TtsProvider>().stop();
    }
  }

  void _toggleMute() {
    Haptics.light();
    setState(() {
      _isMuted = !_isMuted;
    });
    if (_isMuted) {
      _stopLiveListening();
    } else {
      _startLiveListening();
    }
  }

  void _handleHangup() {
    Haptics.medium();
    _speechPauseTimer?.cancel();
    _stopLiveListening();
    context.read<TtsProvider>().stop();
    widget.onHangup();
  }

  void _handleSendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _focusNode.unfocus();
    Haptics.light();
    _stopLiveListening();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final asr = context.watch<AsrProvider>();
    final tts = context.watch<TtsProvider>();

    _handleAsrUpdate(asr);

    final isListening = asr.isListening && !_isMuted;
    final isSpeaking = tts.isSpeaking && _speakerEnabled;

    const controlBg = Color(0xFF262626);
    const inputBg = Color(0xFF1E1E1E);
    const hangupBg = Color(0xFFFF453A); // Coral red

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewInsets.bottom > 0
            ? 12
            : MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F2F7),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Action Controls [ 📹 ]  [ 🔊 ]  [ 🎤 ••••• ]  [ ⚙️ ]
          Row(
            children: [
              // Camera button
              Expanded(
                child: _buildControlPill(
                  icon: Lucide.Video,
                  bg: controlBg,
                  onTap: _handleCameraCapture,
                ),
              ),
              const SizedBox(width: 8),

              // Speaker button
              Expanded(
                child: _buildControlPill(
                  icon: _speakerEnabled ? Lucide.Volume2 : Lucide.VolumeX,
                  iconColor: _speakerEnabled ? Colors.white : Colors.white38,
                  bg: controlBg,
                  onTap: _toggleSpeaker,
                ),
              ),
              const SizedBox(width: 8),

              // Mic button with animated soundwave dots
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isMuted
                          ? const Color(0xFF333333)
                          : (isListening
                              ? const Color(0xFF2D3748)
                              : controlBg),
                      borderRadius: BorderRadius.circular(22),
                      border: isListening
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isMuted ? Lucide.MicOff : Lucide.Mic,
                          size: 18,
                          color: _isMuted ? Colors.white38 : Colors.white,
                        ),
                        const SizedBox(height: 3),
                        // 5 Animated Dancing Dots
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (index) {
                            return AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                double scale = 1.0;
                                if (isListening) {
                                  final phase =
                                      (_pulseController.value * 2 * math.pi) +
                                          (index * 0.8);
                                  scale = 0.8 + 0.6 * math.sin(scale + phase).abs();
                                } else if (isSpeaking) {
                                  scale = 0.9 + 0.4 * (index % 2 == 0 ? 1 : 0.5);
                                } else if (_isMuted) {
                                  scale = 0.5;
                                }
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  width: 3.5,
                                  height: 3.5 * scale,
                                  decoration: BoxDecoration(
                                    color: _isMuted
                                        ? Colors.white24
                                        : (isListening
                                            ? const Color(0xFF68D391)
                                            : Colors.white.withValues(alpha: 0.7)),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Settings button
              Expanded(
                child: _buildControlPill(
                  icon: Lucide.Settings,
                  bg: controlBg,
                  onTap: () {
                    Haptics.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TtsSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Text Input Field + Red Hangup Button [ + Ask anything ]  [ 📞 ]
          Row(
            children: [
              // Text input pill
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Lucide.Plus,
                        size: 18,
                        color: Color(0xFF8E8E93),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Ask anything',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF8E8E93),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _handleSendText(),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _textController,
                        builder: (context, val, _) {
                          if (val.text.trim().isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return GestureDetector(
                            onTap: _handleSendText,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Lucide.ArrowUp,
                                size: 14,
                                color: Colors.black,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Red Hangup Button
              GestureDetector(
                onTap: _handleHangup,
                child: Container(
                  width: 88,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hangupBg,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: hangupBg.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Lucide.PhoneOff,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlPill({
    required IconData icon,
    Color? iconColor,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: iconColor ?? Colors.white,
          ),
        ),
      ),
    );
  }
}
