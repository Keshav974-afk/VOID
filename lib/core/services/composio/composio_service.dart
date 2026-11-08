import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'composio_models.dart';

class ComposioService {
  ComposioService._();
  static final ComposioService instance = ComposioService._();

  static const String _prefsApiKey = 'composio_api_key';
  static const String _v3BaseUrl = 'https://backend.composio.dev/api/v3.1';
  static const String _v3ConnectBaseUrl = 'https://backend.composio.dev/api/v3';

  http.Client _client = http.Client();
  String? lastAuthError;
  bool isLiveCatalog = false;

  String? _cachedApiKey;

  @visibleForTesting
  void setClientForTesting(http.Client client) {
    _client = client;
  }

  Future<String?> getStoredApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedApiKey = prefs.getString(_prefsApiKey);
    return _cachedApiKey;
  }

  Future<void> setStoredApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key.trim();
    _cachedApiKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await prefs.remove(_prefsApiKey);
    } else {
      await prefs.setString(_prefsApiKey, trimmed);
    }
  }

  /// Resolves the active Composio API key from passed key, stored key, or headers.
  Future<String?> resolveApiKey({
    String? explicitKey,
    Map<String, String>? headers,
  }) async {
    if (explicitKey != null && explicitKey.trim().isNotEmpty) {
      return explicitKey.trim();
    }
    if (headers != null) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'x-api-key' &&
            entry.value.trim().isNotEmpty) {
          return entry.value.trim();
        }
        if (entry.key.toLowerCase() == 'x-consumer-api-key' &&
            entry.value.trim().isNotEmpty) {
          return entry.value.trim();
        }
      }
    }
    return getStoredApiKey();
  }

  /// Validates a Composio key against the relevant endpoint.
  Future<({bool isValid, String? error, bool isConsumer})> validateKey(
    String rawKey,
  ) async {
    final key = rawKey.trim();
    if (key.isEmpty) {
      return (
        isValid: false,
        error: 'API key cannot be empty',
        isConsumer: false,
      );
    }

    if (key.startsWith('ck_')) {
      try {
        final res = await _client
            .post(
              Uri.parse('https://connect.composio.dev/mcp'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json, text/event-stream',
                'x-consumer-api-key': key,
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'initialize',
                'params': {
                  'protocolVersion': '2024-11-05',
                  'capabilities': {},
                  'clientInfo': {'name': 'VOID', 'version': '1.0.0'},
                },
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          lastAuthError = null;
          isLiveCatalog = true;
          return (isValid: true, error: null, isConsumer: true);
        } else if (res.statusCode == 401) {
          final err = 'Invalid or expired Consumer API key (HTTP 401)';
          lastAuthError = err;
          isLiveCatalog = false;
          return (isValid: false, error: err, isConsumer: true);
        } else {
          final err = 'Composio MCP server returned HTTP ${res.statusCode}';
          lastAuthError = err;
          isLiveCatalog = false;
          return (isValid: false, error: err, isConsumer: true);
        }
      } catch (e) {
        final err = 'Connection error: $e';
        lastAuthError = err;
        isLiveCatalog = false;
        return (isValid: false, error: err, isConsumer: true);
      }
    } else {
      try {
        final uri = Uri.parse('$_v3BaseUrl/toolkits?limit=1');
        final res = await _client
            .get(
              uri,
              headers: {'x-api-key': key, 'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          lastAuthError = null;
          isLiveCatalog = true;
          return (isValid: true, error: null, isConsumer: false);
        } else if (res.statusCode == 401) {
          final err = 'Invalid or inactive Composio API key (HTTP 401)';
          lastAuthError = err;
          isLiveCatalog = false;
          return (isValid: false, error: err, isConsumer: false);
        } else {
          final err = 'Composio server returned HTTP ${res.statusCode}';
          lastAuthError = err;
          isLiveCatalog = false;
          return (isValid: false, error: err, isConsumer: false);
        }
      } catch (e) {
        final err = 'Connection error: $e';
        lastAuthError = err;
        isLiveCatalog = false;
        return (isValid: false, error: err, isConsumer: false);
      }
    }
  }

  /// Fetches toolkits/connectors from Composio or returns curated catalog.
  Future<List<ComposioToolkit>> fetchToolkits({
    String? apiKey,
    String? search,
    String? category,
  }) async {
    final key = apiKey ?? await getStoredApiKey();
    Set<String> connectedSlugs = {};

    if (key != null && key.isNotEmpty) {
      if (key.startsWith('ck_')) {
        // Consumer MCP mode: query live COMPOSIO_SEARCH_TOOLS on connect.composio.dev/mcp
        try {
          final liveList = await _fetchConsumerToolkits(
            key: key,
            search: search,
            category: category,
          );
          if (liveList.isNotEmpty) {
            lastAuthError = null;
            isLiveCatalog = true;
            return liveList;
          }
        } catch (e) {
          debugPrint(
            '[ComposioService] Live consumer search failed, falling back to curated: $e',
          );
        }
        await validateKey(key);
        return _filterCuratedCatalog(
          search: search,
          category: category,
          connectedSlugs: connectedSlugs,
        );
      }

      try {
        connectedSlugs = await fetchConnectedSlugs(apiKey: key);
      } catch (e) {
        debugPrint('[ComposioService] Error fetching connected accounts: $e');
      }

      try {
        final queryParams = <String, String>{
          'limit': '1000',
          'sort_by': 'usage',
        };
        if (search != null && search.trim().isNotEmpty) {
          queryParams['search'] = search.trim();
        }
        if (category != null &&
            category.trim().isNotEmpty &&
            category.toLowerCase() != 'all') {
          queryParams['category'] = category.trim();
        }

        final uri = Uri.parse(
          '$_v3BaseUrl/toolkits',
        ).replace(queryParameters: queryParams);

        final response = await _client
            .get(
              uri,
              headers: {'x-api-key': key, 'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          List<dynamic> items = [];
          if (data is Map<String, dynamic>) {
            if (data['items'] is List) {
              items = data['items'] as List;
            } else if (data['data'] is List) {
              items = data['data'] as List;
            } else if (data['toolkits'] is List) {
              items = data['toolkits'] as List;
            }
          } else if (data is List) {
            items = data;
          }

          if (items.isNotEmpty) {
            lastAuthError = null;
            isLiveCatalog = true;
            return items.map((item) {
              final map = item as Map<String, dynamic>;
              final slug = (map['slug'] ?? map['key'] ?? map['id'] ?? '')
                  .toString()
                  .toLowerCase();
              final isConnected = connectedSlugs.contains(slug);
              return ComposioToolkit.fromJson(map, isConnected: isConnected);
            }).toList();
          }
        } else if (response.statusCode == 401) {
          lastAuthError = 'Invalid or inactive Composio API key (HTTP 401)';
          isLiveCatalog = false;
        } else {
          lastAuthError =
              'Composio server returned HTTP ${response.statusCode}';
          isLiveCatalog = false;
        }
      } catch (e) {
        debugPrint('[ComposioService] Error fetching live toolkits: $e');
        lastAuthError = 'Network error fetching live toolkits: $e';
        isLiveCatalog = false;
      }
    } else {
      lastAuthError = null;
      isLiveCatalog = false;
    }

    // Fallback to rich curated catalog
    return _filterCuratedCatalog(
      search: search,
      category: category,
      connectedSlugs: connectedSlugs,
    );
  }

  /// Fetches slugs of currently authenticated accounts.
  Future<Set<String>> fetchConnectedSlugs({required String apiKey}) async {
    final slugs = <String>{};
    if (apiKey.trim().isEmpty) return slugs;

    if (apiKey.startsWith('ck_')) {
      return slugs;
    }

    try {
      final uri = Uri.parse('$_v3ConnectBaseUrl/connected_accounts');
      final res = await _client
          .get(
            uri,
            headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        List<dynamic> items = [];
        if (decoded is Map<String, dynamic>) {
          if (decoded['items'] is List) {
            items = decoded['items'] as List;
          } else if (decoded['data'] is List) {
            items = decoded['data'] as List;
          }
        } else if (decoded is List) {
          items = decoded;
        }

        for (final item in items) {
          if (item is Map<String, dynamic>) {
            final appSlug =
                (item['appSlug'] ??
                        item['toolkitSlug'] ??
                        item['app'] ??
                        item['appName'] ??
                        '')
                    .toString()
                    .toLowerCase();
            final status = (item['status'] ?? '').toString().toUpperCase();
            if (appSlug.isNotEmpty && (status == 'ACTIVE' || status.isEmpty)) {
              slugs.add(appSlug);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ComposioService] Connected accounts fetch error: $e');
    }
    return slugs;
  }

  /// Initiates app connection flow, returning the authorization URL.
  Future<String> getAuthorizationUrl(
    String toolkitSlug, {
    String? apiKey,
    String? userId,
  }) async {
    final key = apiKey ?? await getStoredApiKey();
    final slug = toolkitSlug.trim().toLowerCase();

    if (key != null && key.isNotEmpty) {
      if (key.startsWith('ck_')) {
        try {
          final uri = Uri.parse('https://connect.composio.dev/mcp');
          final response = await _client
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json, text/event-stream',
                  'x-consumer-api-key': key,
                },
                body: jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'method': 'tools/call',
                  'params': {
                    'name': 'COMPOSIO_MANAGE_CONNECTIONS',
                    'arguments': {
                      'toolkits': [
                        {'name': slug, 'action': 'add'},
                      ],
                    },
                  },
                }),
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final lines = response.body.split('\n');
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.startsWith('data:')) {
                final jsonStr = trimmed.substring(5).trim();
                final decoded = jsonDecode(jsonStr);
                if (decoded is Map<String, dynamic> &&
                    decoded['result'] is Map<String, dynamic>) {
                  final content = decoded['result']['content'];
                  if (content is List && content.isNotEmpty) {
                    final text = content[0]['text'];
                    if (text is String) {
                      final inner = jsonDecode(text);
                      final results = inner['data']?['results'];
                      if (results is Map && results[slug] is Map) {
                        final redirectUrl = results[slug]['redirect_url'];
                        if (redirectUrl != null &&
                            redirectUrl.toString().isNotEmpty) {
                          return redirectUrl.toString();
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[ComposioService] MCP auth link error: $e');
        }
      } else {
        try {
          final uri = Uri.parse('$_v3ConnectBaseUrl/connected_accounts/link');
          final response = await _client
              .post(
                uri,
                headers: {'x-api-key': key, 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'user_id': userId ?? 'default_user',
                  'toolkit': slug,
                }),
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              final redirectUrl = data['redirect_url'] ?? data['url'];
              if (redirectUrl != null && redirectUrl.toString().isNotEmpty) {
                return redirectUrl.toString();
              }
            }
          }
        } catch (e) {
          debugPrint('[ComposioService] Error getting auth link: $e');
        }
      }
    }

    // Direct hosted Composio app connection dashboard
    return 'https://app.composio.dev/apps/$slug';
  }

  /// Opens the connection link in system browser.
  Future<bool> connectApp(
    String toolkitSlug, {
    String? apiKey,
    String? userId,
  }) async {
    final url = await getAuthorizationUrl(
      toolkitSlug,
      apiKey: apiKey,
      userId: userId,
    );
    final uri = Uri.tryParse(url);
    if (uri != null) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Creates a prompt for the user to tell the AI agent to connect.
  String getAiConnectPrompt(ComposioToolkit toolkit) {
    return 'Please connect and set up the ${toolkit.name} integration via Composio so you can interact with my ${toolkit.name} workspace.';
  }

  List<ComposioToolkit> _filterCuratedCatalog({
    String? search,
    String? category,
    Set<String> connectedSlugs = const {},
  }) {
    var list = _curatedToolkits.map((t) {
      return t.copyWith(isConnected: connectedSlugs.contains(t.slug));
    }).toList();

    if (category != null &&
        category.isNotEmpty &&
        category.toLowerCase() != 'all') {
      final cat = category.toLowerCase();
      list = list.where((t) => t.category.toLowerCase() == cat).toList();
    }

    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((t) {
        return t.name.toLowerCase().contains(q) ||
            t.slug.toLowerCase().contains(q) ||
            (t.description?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return list;
  }

  Future<List<ComposioToolkit>> _fetchConsumerToolkits({
    required String key,
    String? search,
    String? category,
  }) async {
    final queryList = <Map<String, String>>[];
    final cleanSearch = (search ?? '').trim();
    if (cleanSearch.isNotEmpty) {
      queryList.add({'query': cleanSearch});
    } else {
      queryList.addAll([
        {
          'query':
              'developer tools git linear github jira bitbucket gitlab terminal',
        },
        {
          'query':
              'productivity gmail googlecalendar googledrive googlesheets notion asana clickup trello',
        },
        {
          'query':
              'communication chat slack discord microsoft_teams telegram twitter',
        },
        {
          'query':
              'crm sales marketing hubspot salesforce stripe close zoho airtable supabase',
        },
        {'query': 'cloud database storage snowflake postgresql s3 aws'},
      ]);
    }

    final response = await _client
        .post(
          Uri.parse('https://connect.composio.dev/mcp'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'x-consumer-api-key': key,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
              'name': 'COMPOSIO_SEARCH_TOOLS',
              'arguments': {'queries': queryList},
            },
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final lines = response.body.split('\n');
    final discoveredMap = <String, ComposioToolkit>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final jsonStr = trimmed.substring(5).trim();
      if (jsonStr.isEmpty) continue;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic> &&
            decoded['result'] is Map<String, dynamic>) {
          final content = decoded['result']['content'];
          if (content is List && content.isNotEmpty) {
            final text = content[0]['text'];
            if (text is String) {
              final inner = jsonDecode(text);
              final statuses = inner['data']?['toolkit_connection_statuses'];
              if (statuses is List) {
                for (final st in statuses) {
                  if (st is! Map) continue;
                  final slug = (st['toolkit'] ?? '').toString().toLowerCase();
                  if (slug.isEmpty) continue;
                  final desc = (st['description'] ?? '').toString();
                  final connected = st['has_active_connection'] == true;
                  final name = _formatToolkitName(slug);
                  final cat = _detectToolkitCategory(slug);
                  discoveredMap[slug] = ComposioToolkit(
                    slug: slug,
                    name: name,
                    description: desc.isNotEmpty
                        ? desc
                        : 'Connect with $name via Composio',
                    category: cat,
                    isConnected: connected,
                    logo: 'https://logos.composio.dev/api/$slug',
                  );
                }
              }
              final results = inner['data']?['results'];
              if (results is List) {
                for (final res in results) {
                  if (res is! Map) continue;
                  final toolkits = res['toolkits'];
                  if (toolkits is List) {
                    for (final t in toolkits) {
                      final slug = t.toString().toLowerCase();
                      if (slug.isEmpty || discoveredMap.containsKey(slug)) {
                        continue;
                      }
                      discoveredMap[slug] = ComposioToolkit(
                        slug: slug,
                        name: _formatToolkitName(slug),
                        description:
                            'Connect with ${_formatToolkitName(slug)} via Composio',
                        category: _detectToolkitCategory(slug),
                        isConnected: false,
                        logo: 'https://logos.composio.dev/api/$slug',
                      );
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    if (discoveredMap.isEmpty) {
      return const [];
    }

    // When browsing without specific search, merge remaining offline toolkits
    if (cleanSearch.isEmpty) {
      for (final curated in _curatedToolkits) {
        if (!discoveredMap.containsKey(curated.slug)) {
          discoveredMap[curated.slug] = curated;
        }
      }
    }

    var list = discoveredMap.values.toList();
    if (category != null &&
        category.trim().isNotEmpty &&
        category.toLowerCase() != 'all') {
      final cat = category.trim().toLowerCase();
      list = list.where((t) => t.category.toLowerCase() == cat).toList();
    }
    if (cleanSearch.isNotEmpty) {
      final s = cleanSearch.toLowerCase();
      list = list
          .where(
            (t) =>
                t.name.toLowerCase().contains(s) ||
                t.slug.toLowerCase().contains(s) ||
                (t.description?.toLowerCase().contains(s) ?? false) ||
                t.category.toLowerCase().contains(s),
          )
          .toList();
    }

    // Sort: connected first, then alphabetical
    list.sort((a, b) {
      if (a.isConnected && !b.isConnected) return -1;
      if (!a.isConnected && b.isConnected) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return list;
  }

  static String _formatToolkitName(String slug) {
    final lower = slug.toLowerCase();
    switch (lower) {
      case 'github':
        return 'GitHub';
      case 'gmail':
        return 'Gmail';
      case 'googlecalendar':
        return 'Google Calendar';
      case 'googledrive':
        return 'Google Drive';
      case 'googlesheets':
        return 'Google Sheets';
      case 'googledocs':
        return 'Google Docs';
      case 'googlesuper':
        return 'Google Workspace';
      case 'slack':
        return 'Slack';
      case 'slackbot':
        return 'Slack Bot';
      case 'discord':
        return 'Discord';
      case 'telegram':
        return 'Telegram';
      case 'microsoft_teams':
        return 'Microsoft Teams';
      case 'bitbucket':
        return 'Bitbucket';
      case 'gitlab':
        return 'GitLab';
      case 'hubspot':
        return 'HubSpot';
      case 'salesforce':
        return 'Salesforce';
      case 'stripe':
        return 'Stripe';
      case 'linear':
        return 'Linear';
      case 'notion':
        return 'Notion';
      case 'asana':
        return 'Asana';
      case 'clickup':
        return 'ClickUp';
      case 'trello':
        return 'Trello';
      case 'jira':
        return 'Jira';
      case 'supabase':
        return 'Supabase';
      case 'airtable':
        return 'Airtable';
      case 'snowflake':
        return 'Snowflake';
      case 'zoho':
        return 'Zoho CRM';
      case 'close':
        return 'Close CRM';
      default:
        return slug
            .split(RegExp(r'[-_]'))
            .map((word) {
              if (word.isEmpty) return '';
              return word[0].toUpperCase() + word.substring(1);
            })
            .join(' ');
    }
  }

  static String _detectToolkitCategory(String slug) {
    final s = slug.toLowerCase();
    if (s.contains('git') ||
        s.contains('code') ||
        s.contains('terminal') ||
        s.contains('linear') ||
        s.contains('jira')) {
      return 'Developer Tools';
    }
    if (s.contains('mail') ||
        s.contains('calendar') ||
        s.contains('sheet') ||
        s.contains('doc') ||
        s.contains('drive') ||
        s.contains('notion') ||
        s.contains('trello') ||
        s.contains('asana') ||
        s.contains('clickup') ||
        s.contains('task')) {
      return 'Productivity';
    }
    if (s.contains('slack') ||
        s.contains('discord') ||
        s.contains('team') ||
        s.contains('tele') ||
        s.contains('chat') ||
        s.contains('zoom') ||
        s.contains('meet')) {
      return 'Communication';
    }
    if (s.contains('hubspot') ||
        s.contains('salesforce') ||
        s.contains('crm') ||
        s.contains('close') ||
        s.contains('zoho') ||
        s.contains('lead') ||
        s.contains('zendesk')) {
      return 'CRM';
    }
    if (s.contains('stripe') ||
        s.contains('pay') ||
        s.contains('invoice') ||
        s.contains('billing') ||
        s.contains('bank')) {
      return 'Finance';
    }
    if (s.contains('base') ||
        s.contains('sql') ||
        s.contains('db') ||
        s.contains('store') ||
        s.contains('s3') ||
        s.contains('cloud') ||
        s.contains('snowflake')) {
      return 'Cloud & Storage';
    }
    return 'Productivity';
  }

  static const List<ComposioToolkit> _curatedToolkits = [
    // Productivity
    ComposioToolkit(
      slug: 'googledocs',
      name: 'Google Docs',
      description: 'Create, format, read, append, and export documents.',
      category: 'Productivity',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'googlesheets',
      name: 'Google Sheets',
      description:
          'Read and write rows, query cells, format sheets, and automate formulas.',
      category: 'Productivity',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'googlecalendar',
      name: 'Google Calendar',
      description:
          'Create and list meetings, manage calendars, and invite attendees.',
      category: 'Productivity',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'googletasks',
      name: 'Google Tasks',
      description:
          'Manage personal tasks, task lists, and recurring due dates.',
      category: 'Productivity',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'notion',
      name: 'Notion',
      description:
          'Search workspaces, query databases, append blocks, and create pages.',
      category: 'Productivity',
      toolCount: 34,
    ),
    ComposioToolkit(
      slug: 'airtable',
      name: 'Airtable',
      description:
          'Read and update records in relational Airtable spreadsheets and bases.',
      category: 'Productivity',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'coda',
      name: 'Coda',
      description:
          'Manage interactive docs, canvas pages, row tables, and automations.',
      category: 'Productivity',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'trello',
      name: 'Trello',
      description:
          'Manage cards, boards, lists, checklists, and project deadlines.',
      category: 'Productivity',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'asana',
      name: 'Asana',
      description:
          'Create tasks, assign deadlines, organize project boards, and tag milestones.',
      category: 'Productivity',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'clickup',
      name: 'ClickUp',
      description:
          'Track team goals, custom task fields, checklists, and sprint documents.',
      category: 'Productivity',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'monday',
      name: 'Monday.com',
      description:
          'Manage team workflows, column values, board pulses, and timeline items.',
      category: 'Productivity',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'todoist',
      name: 'Todoist',
      description:
          'Create tasks, labels, projects, priorities, and smart filters.',
      category: 'Productivity',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'ticktick',
      name: 'TickTick',
      description:
          'Manage checklists, pomodoro timers, habit trackers, and task calendars.',
      category: 'Productivity',
      toolCount: 15,
    ),
    ComposioToolkit(
      slug: 'confluence',
      name: 'Confluence',
      description:
          'Create technical documentation, spaces, blueprints, and team wikis.',
      category: 'Productivity',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'evernote',
      name: 'Evernote',
      description:
          'Capture notes, search notebooks, clip web pages, and manage tags.',
      category: 'Productivity',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'obsidian',
      name: 'Obsidian',
      description:
          'Sync markdown notes, link bidirectional knowledge graphs, and canvas files.',
      category: 'Productivity',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'basecamp',
      name: 'Basecamp',
      description:
          'Coordinate projects, campfires, message boards, and check-ins.',
      category: 'Productivity',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'onenote',
      name: 'Microsoft OneNote',
      description:
          'Create notebooks, section groups, rich note pages, and drawing notes.',
      category: 'Productivity',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'clockify',
      name: 'Clockify',
      description:
          'Track billable hours, project timesheets, and productivity reports.',
      category: 'Productivity',
      toolCount: 15,
    ),
    ComposioToolkit(
      slug: 'toggl',
      name: 'Toggl Track',
      description:
          'Log time entries, manage clients, workspace tags, and report summaries.',
      category: 'Productivity',
      toolCount: 16,
    ),

    // Developer Tools
    ComposioToolkit(
      slug: 'github',
      name: 'GitHub',
      description:
          'Manage repositories, issues, pull requests, commits, and releases.',
      category: 'Developer Tools',
      toolCount: 46,
    ),
    ComposioToolkit(
      slug: 'gitlab',
      name: 'GitLab',
      description:
          'Manage repositories, merge requests, CI/CD pipelines, and project issues.',
      category: 'Developer Tools',
      toolCount: 34,
    ),
    ComposioToolkit(
      slug: 'bitbucket',
      name: 'Bitbucket',
      description:
          'Manage git repositories, branch permissions, pull requests, and pipelines.',
      category: 'Developer Tools',
      toolCount: 25,
    ),
    ComposioToolkit(
      slug: 'linear',
      name: 'Linear',
      description:
          'Create issues, manage sprints, update task status, and track cycles.',
      category: 'Developer Tools',
      toolCount: 32,
    ),
    ComposioToolkit(
      slug: 'jira',
      name: 'Jira',
      description:
          'Track agile issues, assign tickets, manage workflows, and update roadmaps.',
      category: 'Developer Tools',
      toolCount: 38,
    ),
    ComposioToolkit(
      slug: 'supabase',
      name: 'Supabase',
      description:
          'Query PostgreSQL tables, manage database records, and invoke edge functions.',
      category: 'Developer Tools',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'postgresql',
      name: 'PostgreSQL',
      description:
          'Execute SQL queries, inspect tables, manage schemas, and run transactions.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'mysql',
      name: 'MySQL',
      description:
          'Execute relational database queries, table operations, and index analysis.',
      category: 'Developer Tools',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'redis',
      name: 'Redis',
      description:
          'Read and write key-value pairs, hash sets, publish/subscribe, and cache items.',
      category: 'Developer Tools',
      toolCount: 15,
    ),
    ComposioToolkit(
      slug: 'mongodb',
      name: 'MongoDB',
      description:
          'Query NoSQL collections, aggregate documents, and update BSON records.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'docker',
      name: 'Docker',
      description:
          'List containers, manage images, inspect logs, and control daemon containers.',
      category: 'Developer Tools',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'kubernetes',
      name: 'Kubernetes',
      description:
          'Inspect pods, deployments, configmaps, services, and namespace resources.',
      category: 'Developer Tools',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'aws',
      name: 'AWS',
      description:
          'Manage S3 buckets, EC2 instances, Lambda functions, and CloudWatch metrics.',
      category: 'Developer Tools',
      toolCount: 38,
    ),
    ComposioToolkit(
      slug: 'googlecloud',
      name: 'Google Cloud',
      description:
          'Manage Cloud Storage buckets, BigQuery datasets, Compute Engine, and IAM.',
      category: 'Developer Tools',
      toolCount: 35,
    ),
    ComposioToolkit(
      slug: 'cloudflare',
      name: 'Cloudflare',
      description:
          'Manage DNS zones, Workers, KV storage, R2 buckets, and security rules.',
      category: 'Developer Tools',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'vercel',
      name: 'Vercel',
      description:
          'Inspect deployments, manage project environments, and trigger production builds.',
      category: 'Developer Tools',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'netlify',
      name: 'Netlify',
      description:
          'Manage web deployments, form submissions, edge functions, and site DNS.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'railway',
      name: 'Railway',
      description:
          'Provision databases, manage microservices, set environment variables, and view logs.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'render',
      name: 'Render',
      description:
          'Trigger deploys, monitor web services, managed PostgreSQL, and background jobs.',
      category: 'Developer Tools',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'neon',
      name: 'Neon',
      description:
          'Manage serverless Postgres branches, connection strings, and database pools.',
      category: 'Developer Tools',
      toolCount: 15,
    ),
    ComposioToolkit(
      slug: 'planetscale',
      name: 'PlanetScale',
      description:
          'Create database branches, execute safe schema migrations, and review query insights.',
      category: 'Developer Tools',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'sentry',
      name: 'Sentry',
      description:
          'Retrieve real-time error issues, inspect stack traces, and manage alerts.',
      category: 'Developer Tools',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'datadog',
      name: 'Datadog',
      description:
          'Query APM traces, monitor infrastructure metrics, and view incident dashboards.',
      category: 'Developer Tools',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'grafana',
      name: 'Grafana',
      description:
          'Query Prometheus dashboards, inspect alert rules, and render visualization panels.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'postman',
      name: 'Postman',
      description:
          'Run API collections, manage environment variables, and inspect mock servers.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'snyk',
      name: 'Snyk',
      description:
          'Scan vulnerabilities, container security issues, and open-source licenses.',
      category: 'Developer Tools',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'npm',
      name: 'NPM',
      description:
          'Inspect JavaScript packages, version releases, dependencies, and download stats.',
      category: 'Developer Tools',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'pypi',
      name: 'PyPI',
      description:
          'Query Python package releases, classifiers, metadata, and wheel distributions.',
      category: 'Developer Tools',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'terraform',
      name: 'Terraform Cloud',
      description:
          'Trigger plan runs, inspect state files, and manage workspace variables.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'posthog',
      name: 'PostHog',
      description:
          'Query product analytics, user session recordings, feature flags, and funnels.',
      category: 'Developer Tools',
      toolCount: 20,
    ),

    // Communication
    ComposioToolkit(
      slug: 'slack',
      name: 'Slack',
      description:
          'Send messages, read channels, manage threads, and trigger reminders.',
      category: 'Communication',
      toolCount: 38,
    ),
    ComposioToolkit(
      slug: 'discord',
      name: 'Discord',
      description:
          'Post messages, listen to channels, manage webhooks, and moderate servers.',
      category: 'Communication',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'gmail',
      name: 'Gmail',
      description:
          'Draft emails, send messages, read inbox, and manage email labels.',
      category: 'Communication',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'outlook',
      name: 'Microsoft Outlook',
      description:
          'Send emails, read Microsoft 365 inboxes, and manage contact folders.',
      category: 'Communication',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'microsoftteams',
      name: 'Microsoft Teams',
      description:
          'Post channel announcements, send chat messages, and manage team tabs.',
      category: 'Communication',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'telegram',
      name: 'Telegram',
      description:
          'Send bot messages, manage chat channels, send photos, and handle inline queries.',
      category: 'Communication',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'whatsapp',
      name: 'WhatsApp Business',
      description:
          'Send templated notifications, receive customer messages, and manage media.',
      category: 'Communication',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'twilio',
      name: 'Twilio',
      description:
          'Send SMS messages, place voice calls, verify phone numbers, and fetch logs.',
      category: 'Communication',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'zoom',
      name: 'Zoom',
      description:
          'Schedule video conferences, retrieve recordings, and generate meeting links.',
      category: 'Communication',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'googlemeet',
      name: 'Google Meet',
      description:
          'Generate meeting spaces, manage artifacts, and inspect conference transcripts.',
      category: 'Communication',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'sendgrid',
      name: 'SendGrid',
      description:
          'Send transactional emails, verify delivery events, and query bounce lists.',
      category: 'Communication',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'mailchimp',
      name: 'Mailchimp',
      description:
          'Manage email subscriber audiences, campaign drafts, and delivery analytics.',
      category: 'Communication',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'resend',
      name: 'Resend',
      description:
          'Send modern developer emails, manage custom domains, and view deliverability.',
      category: 'Communication',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'postmark',
      name: 'Postmark',
      description:
          'Send transactional and inbound emails, view delivery streams, and parse webhooks.',
      category: 'Communication',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'intercom',
      name: 'Intercom',
      description:
          'Send conversational messages, read visitor conversations, and manage help desk.',
      category: 'Communication',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'front',
      name: 'Front',
      description:
          'Manage shared team inboxes, comment on email threads, and assign conversations.',
      category: 'Communication',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'crisp',
      name: 'Crisp',
      description:
          'Live customer chat, contact timelines, automated campaigns, and message events.',
      category: 'Communication',
      toolCount: 16,
    ),

    // CRM
    ComposioToolkit(
      slug: 'hubspot',
      name: 'HubSpot',
      description:
          'Manage CRM contacts, companies, deals, tickets, and email campaigns.',
      category: 'CRM',
      toolCount: 38,
    ),
    ComposioToolkit(
      slug: 'salesforce',
      name: 'Salesforce',
      description:
          'Query enterprise leads, opportunities, accounts, and contact records.',
      category: 'CRM',
      toolCount: 42,
    ),
    ComposioToolkit(
      slug: 'pipedrive',
      name: 'Pipedrive',
      description:
          'Manage sales deals, activity schedules, pipeline stages, and organization contacts.',
      category: 'CRM',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'zohocrm',
      name: 'Zoho CRM',
      description:
          'Track sales leads, customer accounts, deal conversions, and sales invoices.',
      category: 'CRM',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'close',
      name: 'Close',
      description:
          'Track sales pipeline, log calls, send sales emails, and manage custom leads.',
      category: 'CRM',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'attio',
      name: 'Attio',
      description:
          'Create custom relationship objects, relationship attributes, and deal lists.',
      category: 'CRM',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'zendesk',
      name: 'Zendesk',
      description:
          'Manage customer support tickets, satisfaction ratings, and knowledgebase.',
      category: 'CRM',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'freshdesk',
      name: 'Freshdesk',
      description:
          'Assign help tickets, automate support agent workflows, and view resolution SLAs.',
      category: 'CRM',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'freshsales',
      name: 'Freshsales',
      description:
          'Manage customer lifecycle, deal pipeline forecasting, and touchpoint timelines.',
      category: 'CRM',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'apollo',
      name: 'Apollo.io',
      description:
          'Enrich B2B lead contacts, search company domains, and launch outreach sequences.',
      category: 'CRM',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'gong',
      name: 'Gong',
      description:
          'Retrieve sales call recordings, conversation transcripts, and competitor mentions.',
      category: 'CRM',
      toolCount: 16,
    ),

    // Social
    ComposioToolkit(
      slug: 'twitter',
      name: 'Twitter / X',
      description:
          'Post tweets, search feeds, retrieve user timelines, and engage with users.',
      category: 'Social',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'linkedin',
      name: 'LinkedIn',
      description:
          'Share company updates, publish article posts, and fetch organizational profiles.',
      category: 'Social',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'reddit',
      name: 'Reddit',
      description:
          'Search subreddits, read post discussions, submit comments, and track topics.',
      category: 'Social',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'youtube',
      name: 'YouTube',
      description:
          'Search videos, fetch comments, view video details, and manage playlists.',
      category: 'Social',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'tiktok',
      name: 'TikTok',
      description:
          'Publish video content, inspect creator statistics, and query user interactions.',
      category: 'Social',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'instagram',
      name: 'Instagram',
      description:
          'Publish photos, carousel posts, retrieve insights, and manage comment threads.',
      category: 'Social',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'facebook',
      name: 'Facebook Pages',
      description:
          'Publish page posts, inspect audience engagement, and manage business events.',
      category: 'Social',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'threads',
      name: 'Threads',
      description:
          'Publish conversational threads, retrieve replies, and manage account posts.',
      category: 'Social',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'medium',
      name: 'Medium',
      description:
          'Draft publications, publish formatted story posts, and inspect readership stats.',
      category: 'Social',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'substack',
      name: 'Substack',
      description:
          'Publish newsletter issues, draft subscriber emails, and manage readership lists.',
      category: 'Social',
      toolCount: 12,
    ),
    ComposioToolkit(
      slug: 'twitch',
      name: 'Twitch',
      description:
          'Inspect live channel streams, manage chat messages, and query game categories.',
      category: 'Social',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'spotify',
      name: 'Spotify',
      description:
          'Control playback, search tracks, query playlists, and get user history.',
      category: 'Social',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'pinterest',
      name: 'Pinterest',
      description:
          'Create visual pins, organize inspiration boards, and query pin engagement metrics.',
      category: 'Social',
      toolCount: 15,
    ),

    // Finance
    ComposioToolkit(
      slug: 'stripe',
      name: 'Stripe',
      description:
          'Process payments, retrieve customer balances, and manage subscriptions.',
      category: 'Finance',
      toolCount: 40,
    ),
    ComposioToolkit(
      slug: 'paypal',
      name: 'PayPal',
      description:
          'Create payment orders, inspect balance transactions, and issue customer refunds.',
      category: 'Finance',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'square',
      name: 'Square',
      description:
          'Manage point-of-sale catalog, customer invoices, and payment checkout links.',
      category: 'Finance',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'quickbooks',
      name: 'QuickBooks Online',
      description:
          'Manage accounting invoices, bill expenses, customer balances, and ledger accounts.',
      category: 'Finance',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'xero',
      name: 'Xero',
      description:
          'Track business bank transactions, accounts payable, balance sheets, and invoices.',
      category: 'Finance',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'plaid',
      name: 'Plaid',
      description:
          'Link bank accounts, retrieve real-time account balances, and transaction records.',
      category: 'Finance',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'brex',
      name: 'Brex',
      description:
          'Inspect corporate credit card expenses, company spending limits, and receipts.',
      category: 'Finance',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'ramp',
      name: 'Ramp',
      description:
          'Review corporate card transactions, spend policies, and automated vendor bill pay.',
      category: 'Finance',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'wise',
      name: 'Wise',
      description:
          'Execute international currency transfers, manage multi-currency bank accounts.',
      category: 'Finance',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'chargebee',
      name: 'Chargebee',
      description:
          'Manage recurring SaaS billing subscriptions, customer checkout, and tax rules.',
      category: 'Finance',
      toolCount: 22,
    ),

    // Design
    ComposioToolkit(
      slug: 'figma',
      name: 'Figma',
      description:
          'Inspect design components, extract styles, get design comments, and export nodes.',
      category: 'Design',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'canva',
      name: 'Canva',
      description:
          'Create graphic designs, export presentations, and automate image templates.',
      category: 'Design',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'miro',
      name: 'Miro',
      description:
          'Create whiteboard sticky notes, shape diagrams, and collaborate on boards.',
      category: 'Design',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'framer',
      name: 'Framer',
      description:
          'Manage responsive web projects, update CMS items, and trigger site publishing.',
      category: 'Design',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'webflow',
      name: 'Webflow',
      description:
          'Update CMS collection items, publish web pages, and inspect form leads.',
      category: 'Design',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'dribbble',
      name: 'Dribbble',
      description:
          'Query designer shots, portfolio projects, and creative design inspiration.',
      category: 'Design',
      toolCount: 12,
    ),

    // AI & Automation
    ComposioToolkit(
      slug: 'openai',
      name: 'OpenAI',
      description:
          'Execute prompt completions, generate vector embeddings, and invoke Assistants.',
      category: 'AI & Automation',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'anthropic',
      name: 'Anthropic Claude',
      description:
          'Invoke Claude for reasoning, document analysis, and conversational tool execution.',
      category: 'AI & Automation',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'gemini',
      name: 'Google Gemini',
      description:
          'Multimodal generation, long-context document understanding, and real-time vision.',
      category: 'AI & Automation',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'mistral',
      name: 'Mistral AI',
      description:
          'Execute open-weight Mistral and Mixtral models, embeddings, and function calling.',
      category: 'AI & Automation',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'huggingface',
      name: 'Hugging Face',
      description:
          'Query open-source AI models, manage inference endpoints, and datasets.',
      category: 'AI & Automation',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'replicate',
      name: 'Replicate',
      description:
          'Run open-source machine learning models in the cloud via serverless API.',
      category: 'AI & Automation',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'perplexity',
      name: 'Perplexity AI',
      description:
          'Execute web-grounded research queries with citations and source references.',
      category: 'AI & Automation',
      toolCount: 14,
    ),
    ComposioToolkit(
      slug: 'elevenlabs',
      name: 'ElevenLabs',
      description:
          'Generate high-fidelity AI voice synthesis, voice clones, and sound effects.',
      category: 'AI & Automation',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'zapier',
      name: 'Zapier',
      description:
          'Trigger multi-app Zaps, trigger automation hooks, and run transfer actions.',
      category: 'AI & Automation',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'make',
      name: 'Make (Integromat)',
      description:
          'Trigger complex visual workflow scenarios and exchange webhook payloads.',
      category: 'AI & Automation',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'n8n',
      name: 'n8n',
      description:
          'Trigger fair-code workflow automations, execution history, and node activations.',
      category: 'AI & Automation',
      toolCount: 18,
    ),

    // Cloud & Storage
    ComposioToolkit(
      slug: 'googledrive',
      name: 'Google Drive',
      description:
          'Upload, search, read, and share files, folders, and Google Docs documents.',
      category: 'Cloud & Storage',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'dropbox',
      name: 'Dropbox',
      description:
          'Search documents, upload binary files, generate sharing links, and sync folders.',
      category: 'Cloud & Storage',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'box',
      name: 'Box',
      description:
          'Manage enterprise content storage, file metadata, retention, and permissions.',
      category: 'Cloud & Storage',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'onedrive',
      name: 'Microsoft OneDrive',
      description:
          'Sync personal and organizational files, upload large documents, and browse items.',
      category: 'Cloud & Storage',
      toolCount: 24,
    ),
  ];
}
