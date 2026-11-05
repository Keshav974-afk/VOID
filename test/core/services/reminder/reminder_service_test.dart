import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/reminder/reminder_model.dart';
import 'package:Kelivo/core/services/reminder/reminder_service.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReminderModel', () {
    test('ReminderCategory auto-detection and icons', () {
      expect(
        ReminderCategory.fromString('water time drink 500ml'),
        ReminderCategory.water,
      );
      expect(
        ReminderCategory.fromString('Math Exam Study'),
        ReminderCategory.study,
      );
      expect(
        ReminderCategory.fromString('take vitamin d pill'),
        ReminderCategory.medicine,
      );
      expect(
        ReminderCategory.fromString('evening gym workout'),
        ReminderCategory.exercise,
      );

      expect(ReminderCategory.water.icon, Lucide.GlassWater);
      expect(ReminderCategory.study.icon, Lucide.GraduationCap);
      expect(ReminderCategory.medicine.icon, Lucide.Pill);
    });

    test('ReminderItem serialization and deserialization', () {
      final now = DateTime.now();
      final item = ReminderItem(
        id: 'test-123',
        title: 'Drink Water',
        notes: 'Stay hydrated',
        dueAt: now.add(const Duration(minutes: 30)),
        createdAt: now,
        type: ReminderType.alarm,
        category: ReminderCategory.water,
      );

      expect(item.isAlarm, isTrue);
      expect(item.isActive, isTrue);

      final json = item.toJson();
      expect(json['id'], 'test-123');
      expect(json['type'], 'alarm');
      expect(json['category'], 'water');

      final restored = ReminderItem.fromJson(json);
      expect(restored.id, item.id);
      expect(restored.title, item.title);
      expect(restored.type, ReminderType.alarm);
      expect(restored.category, ReminderCategory.water);
    });
  });

  group('ReminderService', () {
    test('schedules and manages active reminders', () async {
      final service = ReminderService.instance;
      await service.init();

      final reminder = await service.scheduleReminder(
        title: 'Drink Water',
        notes: 'Water time',
        dueAt: DateTime.now().add(const Duration(hours: 1)),
        type: ReminderType.alarm,
        category: ReminderCategory.water,
      );

      expect(reminder.title, 'Drink Water');
      expect(reminder.type, ReminderType.alarm);
      expect(reminder.category, ReminderCategory.water);
      expect(service.activeReminders.length, greaterThanOrEqualTo(1));

      // Test snooze
      await service.snooze(reminder.id, 10);
      final snoozed = service.getById(reminder.id);
      expect(snoozed, isNotNull);
      expect(snoozed!.isDismissed, isFalse);

      // Test dismiss
      await service.dismiss(reminder.id);
      final dismissed = service.getById(reminder.id);
      expect(dismissed!.isDismissed, isTrue);

      // Test cancel
      await service.cancel(reminder.id);
      expect(service.getById(reminder.id), isNull);
    });
  });
}
