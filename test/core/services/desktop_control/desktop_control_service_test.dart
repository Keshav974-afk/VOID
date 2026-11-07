import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/desktop_control/desktop_control_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalToolsService.isAskUserTool', () {
    test('identifies all variants of ask user tool', () {
      expect(LocalToolsService.isAskUserTool('ask_user_input_v0'), isTrue);
      expect(LocalToolsService.isAskUserTool('ask_user_input'), isTrue);
      expect(LocalToolsService.isAskUserTool('ask_user_v0'), isTrue);
      expect(LocalToolsService.isAskUserTool('ask_user'), isTrue);
      expect(LocalToolsService.isAskUserTool('ask_question'), isTrue);
      expect(LocalToolsService.isAskUserTool('ask_user_custom'), isTrue);
      expect(LocalToolsService.isAskUserTool('ASK_USER_INPUT_V0'), isTrue);

      expect(LocalToolsService.isAskUserTool('calculate'), isFalse);
      expect(LocalToolsService.isAskUserTool('get_weather'), isFalse);
      expect(LocalToolsService.isAskUserTool('desktop_control'), isFalse);
    });
  });

  group('DesktopControlService read_screen and actions', () {
    test('executeAction handles read_screen and returns structured payload', () async {
      final resStr = await DesktopControlService.instance.executeAction({
        'action': 'read_screen',
      });
      final res = jsonDecode(resStr) as Map<String, dynamic>;
      expect(res['status'], 'ok');
      expect(res['action'], 'read_screen');
      expect(res.containsKey('nodes'), isTrue);
      expect(res.containsKey('screen_text'), isTrue);
      expect(res.containsKey('windows'), isTrue);
      expect(res.containsKey('screen_width'), isTrue);
      expect(res.containsKey('screen_height'), isTrue);
    });

    test('executeAction handles click_text with query', () async {
      final resStr = await DesktopControlService.instance.executeAction({
        'action': 'click_text',
        'query': 'nonexistent_test_window_query_12345',
      });
      final res = jsonDecode(resStr) as Map<String, dynamic>;
      expect(res.containsKey('status'), isTrue);
      expect(res['action'], 'click_text');
    });

    test('executeAction handles system_info', () async {
      final resStr = await DesktopControlService.instance.executeAction({
        'action': 'system_info',
      });
      final res = jsonDecode(resStr) as Map<String, dynamic>;
      expect(res['status'], 'ok');
      expect(res.containsKey('system'), isTrue);
    });
  });
}
