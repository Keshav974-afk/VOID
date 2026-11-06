import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/local_tool_labels.dart';

void main() {
  group('AI Management Tools Definitions', () {
    test('manage_mcp_servers tool definition has expected properties', () {
      final def = LocalToolsService.definitionFor(
        LocalToolNames.manageMcpServers,
      );
      expect(def['function']['name'], 'manage_mcp_servers');
      final params = def['function']['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      expect(props.containsKey('action'), isTrue);
      expect(props.containsKey('id'), isTrue);
      expect(props.containsKey('name'), isTrue);
      expect(props.containsKey('transport'), isTrue);
      expect(props.containsKey('url'), isTrue);
      expect(props.containsKey('headers'), isTrue);
      expect(props.containsKey('command'), isTrue);
      expect(props.containsKey('args'), isTrue);
      expect(props.containsKey('env'), isTrue);
      expect(props.containsKey('enabled'), isTrue);
      expect(params['required'], contains('action'));
    });

    test('manage_providers tool definition has expected properties', () {
      final def = LocalToolsService.definitionFor(
        LocalToolNames.manageProviders,
      );
      expect(def['function']['name'], 'manage_providers');
      final params = def['function']['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      expect(props.containsKey('action'), isTrue);
      expect(props.containsKey('provider'), isTrue);
      expect(props.containsKey('name'), isTrue);
      expect(props.containsKey('api_key'), isTrue);
      expect(props.containsKey('base_url'), isTrue);
      expect(props.containsKey('enabled'), isTrue);
      expect(props.containsKey('models'), isTrue);
      expect(params['required'], contains('action'));
    });

    test('configure_settings tool definition has expected properties', () {
      final def = LocalToolsService.definitionFor(
        LocalToolNames.configureSettings,
      );
      expect(def['function']['name'], 'configure_settings');
      final params = def['function']['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      expect(props.containsKey('action'), isTrue);
      expect(props.containsKey('composio_api_key'), isTrue);
      expect(props.containsKey('theme_mode'), isTrue);
      expect(props.containsKey('search_provider'), isTrue);
      expect(props.containsKey('tts_service'), isTrue);
      expect(params['required'], contains('action'));
    });

    test('desktop_control tool definition has expected properties', () {
      final def = LocalToolsService.definitionFor(
        LocalToolNames.desktopControl,
      );
      expect(def['function']['name'], 'desktop_control');
      final params = def['function']['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      expect(props.containsKey('action'), isTrue);
      expect(props.containsKey('app_name'), isTrue);
      expect(props.containsKey('window_title'), isTrue);
      expect(props.containsKey('x'), isTrue);
      expect(props.containsKey('y'), isTrue);
      expect(props.containsKey('text'), isTrue);
      expect(props.containsKey('keys'), isTrue);
      expect(params['required'], contains('action'));
    });

    test('LocalToolNames.all includes new management tools', () {
      expect(LocalToolNames.all, contains(LocalToolNames.desktopControl));
      expect(LocalToolNames.all, contains(LocalToolNames.manageMcpServers));
      expect(LocalToolNames.all, contains(LocalToolNames.manageProviders));
      expect(LocalToolNames.all, contains(LocalToolNames.configureSettings));
    });

    test('localToolIcon provides distinctive icons for management tools', () {
      expect(localToolIcon(LocalToolNames.desktopControl), Lucide.Monitor);
      expect(localToolIcon(LocalToolNames.manageMcpServers), Lucide.Server);
      expect(localToolIcon(LocalToolNames.manageProviders), Lucide.Boxes);
      expect(
        localToolIcon(LocalToolNames.configureSettings),
        Lucide.SlidersHorizontal,
      );
    });
  });
}
