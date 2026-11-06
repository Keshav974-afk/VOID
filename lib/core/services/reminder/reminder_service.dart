import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/snackbar.dart' show rootNavigatorKey;
import '../haptics.dart';
import '../notification_service.dart';
import 'reminder_alarm_dialog.dart';
import 'reminder_model.dart';

class ReminderService extends ChangeNotifier {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  static const String _storageKey = 'void_reminders_store_v1';

  final List<ReminderItem> _reminders = [];
  final Map<String, Timer> _activeTimers = {};
  StreamSubscription<String>? _reminderTapSub;
  bool _initialized = false;

  List<ReminderItem> get allReminders => List.unmodifiable(_reminders);

  List<ReminderItem> get activeReminders =>
      _reminders.where((r) => r.isActive).toList(growable: false);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadFromStorage();
    _listenToNotificationTaps();
    _armTimers();
  }

  void _listenToNotificationTaps() {
    _reminderTapSub?.cancel();
    _reminderTapSub = NotificationService.reminderTaps.listen((payload) {
      _handlePayloadTap(payload);
    });

    final pending = NotificationService.takePendingReminderPayload();
    if (pending != null) {
      _handlePayloadTap(pending);
    }
  }

  void _handlePayloadTap(String payload) {
    String reminderId;
    bool isAlarm = false;
    if (payload.startsWith('reminder-alarm:')) {
      reminderId = payload.substring('reminder-alarm:'.length);
      isAlarm = true;
    } else if (payload.startsWith('reminder:')) {
      reminderId = payload.substring('reminder:'.length);
    } else {
      return;
    }

    final reminder = getById(reminderId);
    if (reminder != null && isAlarm) {
      _showAlarmPopup(reminder);
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _reminders.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _reminders.add(ReminderItem.fromJson(item));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_reminders.map((r) => r.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  void _armTimers() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();

    final now = DateTime.now();
    for (final reminder in activeReminders) {
      if (reminder.isTriggered) continue;
      final diff = reminder.dueAt.difference(now);
      if (diff.isNegative) {
        // Due right now
        _triggerReminder(reminder.id);
      } else {
        _activeTimers[reminder.id] = Timer(diff, () {
          _triggerReminder(reminder.id);
        });
      }
    }
  }

  Future<ReminderItem> scheduleReminder({
    required String title,
    String? notes,
    required DateTime dueAt,
    ReminderType type = ReminderType.notification,
    ReminderCategory? category,
  }) async {
    final cat =
        category ?? ReminderCategory.fromString('$title ${notes ?? ''}');
    final id = 'rem_${DateTime.now().millisecondsSinceEpoch}_${title.hashCode}';

    final reminder = ReminderItem(
      id: id,
      title: title,
      notes: notes ?? '',
      dueAt: dueAt,
      createdAt: DateTime.now(),
      type: type,
      category: cat,
    );

    _reminders.insert(0, reminder);
    await _saveToStorage();

    // Schedule through platform notifications / alarms
    try {
      await NotificationService.scheduleReminderAt(reminder).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint(
            '[ReminderService] Notification scheduling timed out; continuing in-memory.',
          );
        },
      );
    } catch (e) {
      debugPrint('[ReminderService] Notification scheduling error: $e');
    }

    // Schedule in-memory timer
    final diff = dueAt.difference(DateTime.now());
    if (diff.isNegative) {
      _triggerReminder(id);
    } else {
      _activeTimers[id]?.cancel();
      _activeTimers[id] = Timer(diff, () => _triggerReminder(id));
    }

    notifyListeners();
    return reminder;
  }

  Future<void> _triggerReminder(String reminderId) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId);
    if (index == -1) return;

    final reminder = _reminders[index].copyWith(isTriggered: true);
    _reminders[index] = reminder;
    await _saveToStorage();
    notifyListeners();

    // Sound / Haptic
    Haptics.medium();

    // Show platform notification
    await NotificationService.showReminderNow(reminder);

    // If it's an alarm, present the full-screen dialog overlay immediately if app is active
    if (reminder.isAlarm) {
      _showAlarmPopup(reminder);
    }
  }

  void _showAlarmPopup(ReminderItem reminder) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        showReminderAlarmDialog(ctx, reminder);
      }
    });
  }

  Future<void> snooze(String reminderId, int minutes) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId);
    if (index == -1) return;

    final old = _reminders[index];
    final newDue = DateTime.now().add(Duration(minutes: minutes));
    final updated = old.copyWith(
      dueAt: newDue,
      isTriggered: false,
      isDismissed: false,
    );
    _reminders[index] = updated;
    await _saveToStorage();

    await NotificationService.cancelReminder(reminderId);
    await NotificationService.scheduleReminderAt(updated);

    _activeTimers[reminderId]?.cancel();
    _activeTimers[reminderId] = Timer(
      Duration(minutes: minutes),
      () => _triggerReminder(reminderId),
    );

    notifyListeners();
  }

  Future<void> dismiss(String reminderId) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId);
    if (index == -1) return;

    _reminders[index] = _reminders[index].copyWith(isDismissed: true);
    await _saveToStorage();

    await NotificationService.cancelReminder(reminderId);
    _activeTimers.remove(reminderId)?.cancel();

    notifyListeners();
  }

  Future<void> cancel(String reminderId) async {
    _reminders.removeWhere((r) => r.id == reminderId);
    await _saveToStorage();

    await NotificationService.cancelReminder(reminderId);
    _activeTimers.remove(reminderId)?.cancel();

    notifyListeners();
  }

  ReminderItem? getById(String id) {
    try {
      return _reminders.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _reminderTapSub?.cancel();
    for (final t in _activeTimers.values) {
      t.cancel();
    }
    _activeTimers.clear();
    super.dispose();
  }
}
