import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';
import '../haptics.dart';
import 'reminder_model.dart';
import 'reminder_service.dart';

/// Smooth, theme-aware VOID Reminder Popup Dialog with frosted glass backdrop,
/// spring entrance animation, and quick snooze controls.
Future<void> showReminderAlarmDialog(
  BuildContext context,
  ReminderItem reminder,
) async {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Reminder',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (dialogCtx, _, __) =>
        _ReminderAlarmDialogWidget(reminder: reminder),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10 * fade.value,
          sigmaY: 10 * fade.value,
        ),
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
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
  int _selectedSnoozeMinutes = 5;

  static const List<int> _snoozePresets = [5, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    Haptics.medium();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted) Haptics.light();
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
    Haptics.medium();
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cat = widget.reminder.category;
    final timeStr =
        '${widget.reminder.dueAt.hour.toString().padLeft(2, '0')}:${widget.reminder.dueAt.minute.toString().padLeft(2, '0')}';

    final accentColor = switch (cat) {
      ReminderCategory.water => const Color(0xFF38BDF8),
      ReminderCategory.medicine => const Color(0xFFF43F5E),
      ReminderCategory.exercise => const Color(0xFF10B981),
      ReminderCategory.study => cs.primary,
      ReminderCategory.calendar => const Color(0xFFF59E0B),
      ReminderCategory.task => const Color(0xFF8B5CF6),
      ReminderCategory.general => cs.primary,
    };

    final cardSurface = isDark
        ? const Color(0xFF141418).withValues(alpha: 0.96)
        : cs.surface.withValues(alpha: 0.98);
    final subtleSurface = isDark
        ? const Color(0xFF1E1E24)
        : cs.surfaceContainerHighest.withValues(alpha: 0.55);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : cs.outlineVariant.withValues(alpha: 0.65);

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxWidth: 390),
            decoration: BoxDecoration(
              color: cardSurface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.16),
                  blurRadius: 36,
                  spreadRadius: 2,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top bar: VOID Emblem + Category Pill + Time Pill
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.30),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const VoidLogo(size: 13),
                            const SizedBox(width: 6),
                            Text(
                              cat.label.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: AppFontWeights.semibold,
                                letterSpacing: 0.8,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: subtleSurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Lucide.Clock,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Animated Pulsing Icon Ring
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accentColor.withValues(alpha: 0.22),
                            accentColor.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.38),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.18),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(cat.icon, size: 30, color: accentColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Reminder Title
                  Text(
                    widget.reminder.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: AppFontWeights.emphasis,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),

                  // Optional Notes
                  if (widget.reminder.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: subtleSurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.reminder.notes.trim(),
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppFontWeights.regular,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Quick Snooze Duration Pills
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _snoozePresets.map((mins) {
                      final selected = _selectedSnoozeMinutes == mins;
                      final label = mins >= 60 ? '+1h' : '+${mins}m';
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Haptics.light();
                            setState(() => _selectedSnoozeMinutes = mins);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? accentColor.withValues(alpha: 0.16)
                                  : subtleSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? accentColor.withValues(alpha: 0.55)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? AppFontWeights.semibold
                                    : AppFontWeights.medium,
                                color: selected
                                    ? accentColor
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 18),

                  // Primary Action Row: Snooze & Complete/Dismiss
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _handleSnooze(_selectedSnoozeMinutes),
                          icon: const Icon(Lucide.AlarmClock, size: 16),
                          label: Text(
                            _selectedSnoozeMinutes >= 60
                                ? 'Snooze 1h'
                                : 'Snooze ${_selectedSnoozeMinutes}m',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: AppFontWeights.medium,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: subtleSurface,
                            foregroundColor: cs.onSurface,
                            side: BorderSide(color: borderColor, width: 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _handleDismiss,
                          icon: const Icon(Lucide.Check, size: 16),
                          label: Text(
                            'Complete',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
      ),
    );
  }
}
