import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/composio/composio_models.dart';
import 'package:Kelivo/core/services/composio/composio_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ComposioService', () {
    test('filters curated catalog by search and category', () async {
      final all = await ComposioService.instance.fetchToolkits();
      expect(all, isNotEmpty);
      expect(all.any((t) => t.slug == 'github'), isTrue);

      final devTools = await ComposioService.instance.fetchToolkits(
        category: 'Developer Tools',
      );
      expect(devTools.every((t) => t.category == 'Developer Tools'), isTrue);

      final searchSlack = await ComposioService.instance.fetchToolkits(
        search: 'slack',
      );
      expect(searchSlack.length, 1);
      expect(searchSlack.first.slug, 'slack');
    });

    test('parses live toolkits and marks connected', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('connected_accounts')) {
          return http.Response(
            jsonEncode({
              'items': [
                {'appSlug': 'github', 'status': 'ACTIVE'},
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('toolkits')) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'slug': 'github',
                  'name': 'GitHub',
                  'category': 'Developer Tools',
                  'logo': 'https://assets.composio.dev/icons/github.svg',
                  'toolCount': 42,
                },
                {
                  'slug': 'gmail',
                  'name': 'Gmail',
                  'category': 'Communication',
                  'logo': 'https://assets.composio.dev/icons/gmail.svg',
                  'toolCount': 28,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ComposioService.instance.setClientForTesting(mockClient);
      final toolkits = await ComposioService.instance.fetchToolkits(
        apiKey: 'test-api-key',
      );

      expect(toolkits.length, 2);
      final github = toolkits.firstWhere((t) => t.slug == 'github');
      expect(github.isConnected, isTrue);

      final gmail = toolkits.firstWhere((t) => t.slug == 'gmail');
      expect(gmail.isConnected, isFalse);
    });

    test('generates AI connect prompt correctly', () {
      const toolkit = ComposioToolkit(
        slug: 'linear',
        name: 'Linear',
        category: 'Developer Tools',
      );
      final prompt = ComposioService.instance.getAiConnectPrompt(toolkit);
      expect(prompt, contains('Linear'));
      expect(prompt, contains('Composio'));
    });
  });

  group('LocalToolsService composio_connect tool', () {
    test('defines composio_connect with required parameters', () {
      final def = LocalToolsService.definitionFor(
        LocalToolNames.composioConnect,
      );
      expect(def['function']['name'], 'composio_connect');
      expect(def['function']['parameters']['properties'], contains('app'));
      expect(def['function']['parameters']['properties'], contains('action'));
    });

    test('executes composio_connect for auth link', () async {
      final resultJson = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.composioConnect,
        {'app': 'slack', 'action': 'connect'},
        null,
      );

      final decoded = jsonDecode(resultJson!) as Map<String, dynamic>;
      expect(decoded['status'], 'needs_auth');
      expect(decoded['app'], 'slack');
      expect(decoded['auth_url'], contains('composio.dev'));
    });

    test('executes composio_connect action list', () async {
      final resultJson = await LocalToolsService.tryHandleToolCall(
        LocalToolNames.composioConnect,
        {'action': 'list', 'app': 'all'},
        null,
      );

      final decoded = jsonDecode(resultJson!) as Map<String, dynamic>;
      expect(decoded['status'], 'success');
      expect(decoded['action'], 'list');
      expect(decoded['connectors'], isNotEmpty);
    });
  });
}
