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

    test('resolves logoUrl to logos.composio.dev/api/{slug}', () {
      const t1 = ComposioToolkit(slug: 'github', name: 'GitHub');
      expect(t1.logoUrl, 'https://logos.composio.dev/api/github');

      const t2 = ComposioToolkit(
        slug: 'slack',
        name: 'Slack',
        logo: 'https://assets.composio.dev/icons/slack.svg',
      );
      expect(t2.logoUrl, 'https://logos.composio.dev/api/slack');

      const t3 = ComposioToolkit(
        slug: 'custom',
        name: 'Custom',
        logo: 'https://custom.com/icon.png',
      );
      expect(t3.logoUrl, 'https://custom.com/icon.png');
    });

    test('validates consumer key (ck_) via MCP endpoint', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == 'https://connect.composio.dev/mcp') {
          return http.Response(
            ': connected\n\nevent: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}\n\n',
            200,
          );
        }
        return http.Response('Unauthorized', 401);
      });

      ComposioService.instance.setClientForTesting(mockClient);
      final res = await ComposioService.instance.validateKey(
        'ck_test_consumer_key',
      );
      expect(res.isValid, isTrue);
      expect(res.isConsumer, isTrue);
      expect(res.error, isNull);
    });

    test('validates project key (ak_) via toolkits endpoint', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('toolkits')) {
          return http.Response(jsonEncode({'items': []}), 200);
        }
        return http.Response('Unauthorized', 401);
      });

      ComposioService.instance.setClientForTesting(mockClient);
      final res = await ComposioService.instance.validateKey('ak_live_123456');
      expect(res.isValid, isTrue);
      expect(res.isConsumer, isFalse);
    });

    test(
      'obtains authorization URL for consumer key via MCP MANAGE_CONNECTIONS',
      () async {
        final innerJson = jsonEncode({
          'successful': true,
          'data': {
            'results': {
              'github': {
                'redirect_url': 'https://connect.composio.dev/link/lk_test123',
              },
            },
          },
        });
        final outerJson = jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'content': [
              {'type': 'text', 'text': innerJson},
            ],
          },
        });

        final mockClient = MockClient((request) async {
          if (request.url.toString() == 'https://connect.composio.dev/mcp') {
            final sse = ': connected\n\nevent: message\ndata: $outerJson\n\n';
            return http.Response(sse, 200);
          }
          return http.Response('Not Found', 404);
        });

        ComposioService.instance.setClientForTesting(mockClient);
        final url = await ComposioService.instance.getAuthorizationUrl(
          'github',
          apiKey: 'ck_testkey',
        );
        expect(url, 'https://connect.composio.dev/link/lk_test123');
      },
    );

    test(
      'fetches live consumer toolkits via MCP COMPOSIO_SEARCH_TOOLS',
      () async {
        final innerJson = jsonEncode({
          'successful': true,
          'data': {
            'results': [
              {
                'toolkits': ['github', 'gmail', 'slack'],
              },
            ],
            'toolkit_connection_statuses': [
              {
                'toolkit': 'github',
                'description': 'GitHub code hosting platform',
                'has_active_connection': true,
              },
              {
                'toolkit': 'gmail',
                'description': 'Google Mail',
                'has_active_connection': false,
              },
            ],
          },
        });
        final outerJson = jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'content': [
              {'type': 'text', 'text': innerJson},
            ],
          },
        });

        final mockClient = MockClient((request) async {
          if (request.url.toString() == 'https://connect.composio.dev/mcp') {
            final sse = ': connected\n\nevent: message\ndata: $outerJson\n\n';
            return http.Response(sse, 200);
          }
          return http.Response('Not Found', 404);
        });

        ComposioService.instance.setClientForTesting(mockClient);
        final list = await ComposioService.instance.fetchToolkits(
          apiKey: 'ck_test_key_123',
        );
        expect(list, isNotEmpty);
        final github = list.firstWhere((t) => t.slug == 'github');
        expect(github.isConnected, isTrue);
        expect(github.name, 'GitHub');
        expect(github.description, 'GitHub code hosting platform');
      },
    );
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
