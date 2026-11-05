import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';

enum ReminderType { notification, alarm }

enum ReminderCategory {
  water,
  medicine,
  exercise,
  study,
  calendar,
  task,
  general;

  static ReminderCategory fromString(String? val) {
    if (val == null) return ReminderCategory.general;
    final lower = val.toLowerCase().trim();
    if (lower.contains('water') ||
        lower.contains('drink') ||
        lower.contains('hydrat')) {
      return ReminderCategory.water;
    }
    if (lower.contains('med') ||
        lower.contains('pill') ||
        lower.contains('drug') ||
        lower.contains('vitam')) {
      return ReminderCategory.medicine;
    }
    if (lower.contains('workout') ||
        lower.contains('exercise') ||
        lower.contains('gym') ||
        lower.contains('fit')) {
      return ReminderCategory.exercise;
    }
    if (lower.contains('study') ||
        lower.contains('read') ||
        lower.contains('exam') ||
        lower.contains('homework') ||
        lower.contains('learn') ||
        lower.contains('revision')) {
      return ReminderCategory.study;
    }
    if (lower.contains('meet') ||
        lower.contains('event') ||
        lower.contains('cal')) {
      return ReminderCategory.calendar;
    }
    if (lower.contains('task') ||
        lower.contains('todo') ||
        lower.contains('work')) {
      return ReminderCategory.task;
    }
    return ReminderCategory.general;
  }

  IconData get icon {
    switch (this) {
      case ReminderCategory.water:
        return Lucide.GlassWater;
      case ReminderCategory.medicine:
        return Lucide.Pill;
      case ReminderCategory.exercise:
        return Lucide.Dumbbell;
      case ReminderCategory.study:
        return Lucide.GraduationCap;
      case ReminderCategory.calendar:
        return Lucide.Clock;
      case ReminderCategory.task:
        return Lucide.Check;
      case ReminderCategory.general:
        return Lucide.AlarmClock;
    }
  }

  String get label {
    switch (this) {
      case ReminderCategory.water:
        return 'Water Time';
      case ReminderCategory.medicine:
        return 'Medicine';
      case ReminderCategory.exercise:
        return 'Exercise';
      case ReminderCategory.study:
        return 'Study Time';
      case ReminderCategory.calendar:
        return 'Calendar';
      case ReminderCategory.task:
        return 'Task';
      case ReminderCategory.general:
        return 'Reminder';
    }
  }
}

class ReminderItem {
  ReminderItem({
    required this.id,
    required this.title,
    this.notes = '',
    required this.dueAt,
    required this.createdAt,
    this.type = ReminderType.notification,
    this.category = ReminderCategory.general,
    this.isTriggered = false,
    this.isDismissed = false,
  });

  final String id;
  final String title;
  final String notes;
  final DateTime dueAt;
  final DateTime createdAt;
  final ReminderType type;
  final ReminderCategory category;
  final bool isTriggered;
  final bool isDismissed;

  bool get isAlarm => type == ReminderType.alarm;
  bool get isActive => !isDismissed;

  ReminderItem copyWith({
    String? title,
    String? notes,
    DateTime? dueAt,
    ReminderType? type,
    ReminderCategory? category,
    bool? isTriggered,
    bool? isDismissed,
  }) => ReminderItem(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    dueAt: dueAt ?? this.dueAt,
    createdAt: createdAt,
    type: type ?? this.type,
    category: category ?? this.category,
    isTriggered: isTriggered ?? this.isTriggered,
    isDismissed: isDismissed ?? this.isDismissed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'dueAt': dueAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'type': type.name,
    'category': category.name,
    'isTriggered': isTriggered,
    'isDismissed': isDismissed,
  };

  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: (json['notes'] as String?) ?? '',
    dueAt: DateTime.parse(json['dueAt'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    type: json['type'] == 'alarm'
        ? ReminderType.alarm
        : ReminderType.notification,
    category: ReminderCategory.fromString(json['category'] as String?),
    isTriggered: (json['isTriggered'] as bool?) ?? false,
    isDismissed: (json['isDismissed'] as bool?) ?? false,
  );
}
