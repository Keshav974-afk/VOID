import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/reminder/reminder_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReminderService.instance.init();
  });

  group('LocalToolsService set_reminder tool', () {
    test('defines set_reminder with required parameters', () {
      final def = LocalToolsService.definitionFor(LocalToolNames.setReminder);
      expect(def['function']['name'], 'set_reminder');
      expect(def['function']['parameters']['properties'], contains('title'));
      expect(
        def['function']['parameters']['properties'],
        contains('delay_seconds'),
      );
      expect(def['function']['parameters']['properties'], contains('type'));
      expect(def['function']['parameters']['properties'], contains('category'));
    });

    test('executes set_reminder for water time with alarm popup', () async {
      final resultJson = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.setReminder,
        {
          'title': 'Drink Water',
          'notes': "It's water time!",
          'delay_seconds': 1800,
          'type': 'alarm',
          'category': 'water',
        },
        null,
      );

      final decoded = jsonDecode(resultJson!) as Map<String, dynamic>;
      expect(decoded['status'], 'success');
      expect(decoded['title'], 'Drink Water');
      expect(decoded['type'], 'alarm');
      expect(decoded['category'], 'water');
      expect(decoded['category_label'], 'Water Time');
    });

    test('executes set_reminder for study session with study icon', () async {
      final resultJson = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.setReminder,
        {
          'title': 'Math Exam Study',
          'notes': 'Study chapter 4',
          'delay_seconds': 3600,
          'type': 'notification',
          'category': 'study',
        },
        null,
      );

      final decoded = jsonDecode(resultJson!) as Map<String, dynamic>;
      expect(decoded['status'], 'success');
      expect(decoded['title'], 'Math Exam Study');
      expect(decoded['category'], 'study');
      expect(decoded['category_label'], 'Study Time');
    });
  });
}
