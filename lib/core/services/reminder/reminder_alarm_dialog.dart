import 'dart:async';
import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../haptics.dart';
import 'reminder_model.dart';
import 'reminder_service.dart';

/// Full-screen/modal dark void alarm dialog without emojis or bright colors.
Future<void> showReminderAlarmDialog(
  BuildContext context,
  ReminderItem reminder,
) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (dialogCtx) => _ReminderAlarmDialogWidget(reminder: reminder),
  );
}

class _ReminderAlarmDialogWidget extends StatefulWidget {
  const _ReminderAlarmDialogWidget({required this.reminder});

  final ReminderItem reminder;

  @override
  State<_ReminderAlarmDialogWidget> createState() =>
      _ReminderAlarmDialogWidgetState();
}

class _ReminderAlarmDialogWidgetState extends State<_ReminderAlarmDialogWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial alert haptic
    Haptics.medium();

    // Gentle recurring haptic pulse every 2.5 seconds until dismissed/snoozed
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) Haptics.medium();
    });
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _hapticTimer?.cancel();
    Haptics.light();
    ReminderService.instance.dismiss(widget.reminder.id);
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _handleSnooze(int minutes) {
    _hapticTimer?.cancel();
    Haptics.light();
    ReminderService.instance.snooze(widget.reminder.id, minutes);
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.reminder.category;
    final timeStr =
        '${widget.reminder.dueAt.hour.toString().padLeft(2, '0')}:${widget.reminder.dueAt.minute.toString().padLeft(2, '0')}';

    // Muted VOID color scheme: strictly no bright neon colors and no emojis
    final isWater = cat == ReminderCategory.water;
    final isStudy = cat == ReminderCategory.study;
    final accentColor = isWater
        ? const Color(0xFF7DD3FC) // subtle ice-blue
        : isStudy
        ? const Color(0xFFCBD5E1) // subtle slate
        : const Color(0xFFD4D4D8); // refined silver zinc

    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF121214),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF27272A), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Pulsing Icon Container
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF18181B),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(cat.icon, size: 32, color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Category Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF27272A),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    cat.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: accentColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Reminder Title
                Text(
                  widget.reminder.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF4F4F5),
                    letterSpacing: -0.3,
                  ),
                ),

                // Optional Notes
                if (widget.reminder.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.reminder.notes,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFA1A1AA),
                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Scheduled Time Indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Lucide.Clock,
                      size: 13,
                      color: Color(0xFF71717A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Scheduled at $timeStr',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                // Actions: Snooze 5m & Dismiss
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _handleSnooze(5),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFF18181B),
                          foregroundColor: const Color(0xFFD4D4D8),
                          side: const BorderSide(
                            color: Color(0xFF27272A),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Snooze 5m',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _handleDismiss,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE4E4E7),
                          foregroundColor: const Color(0xFF09090B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Dismiss',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
