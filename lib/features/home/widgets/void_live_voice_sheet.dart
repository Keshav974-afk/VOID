import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/providers/tts_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';

class VoidLiveVoiceSheet extends StatefulWidget {
  const VoidLiveVoiceSheet({super.key, required this.onSendSpokenPrompt});

  final ValueChanged<String> onSendSpokenPrompt;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSendSpokenPrompt,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: VoidLiveVoiceSheet(onSendSpokenPrompt: onSendSpokenPrompt),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          VoidLiveVoiceSheet(onSendSpokenPrompt: onSendSpokenPrompt),
    );
  }

  @override
  State<VoidLiveVoiceSheet> createState() => _VoidLiveVoiceSheetState();
}

class _VoidLiveVoiceSheetState extends State<VoidLiveVoiceSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _orbCtrl;
  bool _speechAvailable = false;
  bool _isListening = false;
  String _liveTranscript = '';
  String _statusText = 'Initializing VOID Live Voice...';

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _statusText = 'Tap the VOID Orb to speak';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = ok;
        _statusText = ok
            ? 'Listening... Speak naturally to VOID'
            : 'Microphone speech engine unavailable on this device';
      });
      if (ok) {
        await _startListening();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _statusText = 'Tap the VOID Orb to start voice session';
      });
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;
    Haptics.light();
    try {
      await context.read<TtsProvider>().stop();
    } catch (_) {}
    setState(() {
      _liveTranscript = '';
      _isListening = true;
      _statusText = 'Listening... Speak to VOID';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _liveTranscript = result.recognizedWords;
        });
        if (result.finalResult && _liveTranscript.trim().isNotEmpty) {
          _dispatchTranscript();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 40),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _stopListeningAndSend() async {
    await _speech.stop();
    if (_liveTranscript.trim().isNotEmpty) {
      _dispatchTranscript();
    } else if (mounted) {
      setState(() {
        _isListening = false;
        _statusText = 'Tap the VOID Orb to speak';
      });
    }
  }

  void _dispatchTranscript() {
    final text = _liveTranscript.trim();
    if (text.isEmpty) return;
    Haptics.medium();
    setState(() {
      _isListening = false;
      _statusText = 'Sent to VOID — Generating response...';
    });
    Navigator.of(context).pop();
    widget.onSendSpokenPrompt(text);
  }

  @override
  void dispose() {
    _speech.stop();
    _orbCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final tts = context.watch<TtsProvider>();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: isDesktop
            ? BorderRadius.circular(28)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF27272A)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Lucide.AudioLines, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'VOID Live Duplex Voice',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Lucide.X, size: 18, color: cs.onSurfaceVariant),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Animated Singularity Voice Orb
            GestureDetector(
              onTap: () {
                if (tts.isSpeaking) {
                  tts.stop();
                  _startListening();
                } else if (_isListening) {
                  _stopListeningAndSend();
                } else {
                  _startListening();
                }
              },
              child: AnimatedBuilder(
                animation: _orbCtrl,
                builder: (ctx, _) {
                  final active = _isListening || tts.isSpeaking;
                  final scale = active
                      ? 1.0 + (_orbCtrl.value * 0.12)
                      : 1.0 + (_orbCtrl.value * 0.03);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            cs.primary.withValues(alpha: active ? 0.28 : 0.12),
                            cs.primary.withValues(alpha: 0.02),
                          ],
                        ),
                        border: Border.all(
                          color: cs.primary.withValues(
                            alpha: active ? 0.65 : 0.25,
                          ),
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(
                              alpha: active ? 0.25 : 0.08,
                            ),
                            blurRadius: active ? 36 : 16,
                            spreadRadius: active ? 4 : 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: VoidLogo(size: 64, glow: true),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            Text(
              tts.isSpeaking
                  ? 'VOID is speaking — Tap Orb to interrupt'
                  : _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141418)
                    : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Center(
                child: Text(
                  _liveTranscript.isEmpty
                      ? '“Ask VOID anything hands-free...”'
                      : _liveTranscript,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: _liveTranscript.isEmpty
                        ? AppFontWeights.regular
                        : AppFontWeights.medium,
                    color: _liveTranscript.isEmpty
                        ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                        : cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isListening
                        ? _stopListeningAndSend
                        : _startListening,
                    icon: Icon(
                      _isListening ? Lucide.MicOff : Lucide.Mic,
                      size: 16,
                    ),
                    label: Text(_isListening ? 'Done Speaking' : 'Listen'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                if (_liveTranscript.trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _dispatchTranscript,
                      icon: const Icon(Lucide.Send, size: 16),
                      label: const Text('Send Now'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
