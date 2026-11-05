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

  @visibleForTesting
  void setClientForTesting(http.Client client) {
    _client = client;
  }

  Future<String?> getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsApiKey);
  }

  Future<void> setStoredApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key.trim();
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
      }
    }
    return getStoredApiKey();
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
      try {
        connectedSlugs = await fetchConnectedSlugs(apiKey: key);
      } catch (e) {
        debugPrint('[ComposioService] Error fetching connected accounts: $e');
      }

      try {
        final queryParams = <String, String>{};
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
        ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

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
            return items.map((item) {
              final map = item as Map<String, dynamic>;
              final slug = (map['slug'] ?? map['key'] ?? map['id'] ?? '')
                  .toString()
                  .toLowerCase();
              final isConnected = connectedSlugs.contains(slug);
              return ComposioToolkit.fromJson(map, isConnected: isConnected);
            }).toList();
          }
        }
      } catch (e) {
        debugPrint('[ComposioService] Error fetching live toolkits: $e');
      }
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

  static const List<ComposioToolkit> _curatedToolkits = [
    ComposioToolkit(
      slug: 'github',
      name: 'GitHub',
      logo: 'https://assets.composio.dev/icons/github.svg',
      description:
          'Manage repositories, issues, pull requests, commits, and releases.',
      category: 'Developer Tools',
      toolCount: 42,
    ),
    ComposioToolkit(
      slug: 'slack',
      name: 'Slack',
      logo: 'https://assets.composio.dev/icons/slack.svg',
      description:
          'Send messages, read channels, manage threads, and trigger reminders.',
      category: 'Communication',
      toolCount: 38,
    ),
    ComposioToolkit(
      slug: 'googlecalendar',
      name: 'Google Calendar',
      logo: 'https://assets.composio.dev/icons/googlecalendar.svg',
      description:
          'Create and list meetings, manage calendars, and invite attendees.',
      category: 'Productivity',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'gmail',
      name: 'Gmail',
      logo: 'https://assets.composio.dev/icons/gmail.svg',
      description:
          'Draft emails, send messages, read inbox, and manage email labels.',
      category: 'Communication',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'googledrive',
      name: 'Google Drive',
      logo: 'https://assets.composio.dev/icons/googledrive.svg',
      description:
          'Upload, search, read, and share files and Google Docs documents.',
      category: 'Productivity',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'notion',
      name: 'Notion',
      logo: 'https://assets.composio.dev/icons/notion.svg',
      description:
          'Search workspaces, query databases, append blocks, and create pages.',
      category: 'Productivity',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'linear',
      name: 'Linear',
      logo: 'https://assets.composio.dev/icons/linear.svg',
      description:
          'Create issues, manage sprints, update task status, and track cycles.',
      category: 'Developer Tools',
      toolCount: 32,
    ),
    ComposioToolkit(
      slug: 'jira',
      name: 'Jira',
      logo: 'https://assets.composio.dev/icons/jira.svg',
      description:
          'Track issues, assign tickets, manage workflows, and update roadmaps.',
      category: 'Developer Tools',
      toolCount: 35,
    ),
    ComposioToolkit(
      slug: 'discord',
      name: 'Discord',
      logo: 'https://assets.composio.dev/icons/discord.svg',
      description:
          'Post messages, listen to channels, manage webhooks, and moderate servers.',
      category: 'Communication',
      toolCount: 25,
    ),
    ComposioToolkit(
      slug: 'twitter',
      name: 'Twitter / X',
      logo: 'https://assets.composio.dev/icons/twitter.svg',
      description:
          'Post tweets, search feeds, retrieve user timelines, and engage with users.',
      category: 'Social',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'trello',
      name: 'Trello',
      logo: 'https://assets.composio.dev/icons/trello.svg',
      description:
          'Manage cards, boards, lists, checklists, and project deadlines.',
      category: 'Productivity',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'stripe',
      name: 'Stripe',
      logo: 'https://assets.composio.dev/icons/stripe.svg',
      description:
          'Process payments, retrieve customer balances, and manage subscriptions.',
      category: 'Finance',
      toolCount: 36,
    ),
    ComposioToolkit(
      slug: 'hubspot',
      name: 'HubSpot',
      logo: 'https://assets.composio.dev/icons/hubspot.svg',
      description:
          'Manage CRM contacts, companies, deals, tickets, and email campaigns.',
      category: 'CRM',
      toolCount: 34,
    ),
    ComposioToolkit(
      slug: 'salesforce',
      name: 'Salesforce',
      logo: 'https://assets.composio.dev/icons/salesforce.svg',
      description:
          'Query enterprise leads, opportunities, accounts, and contact records.',
      category: 'CRM',
      toolCount: 40,
    ),
    ComposioToolkit(
      slug: 'supabase',
      name: 'Supabase',
      logo: 'https://assets.composio.dev/icons/supabase.svg',
      description:
          'Query PostgreSQL tables, manage database records, and invoke edge functions.',
      category: 'Developer Tools',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'vercel',
      name: 'Vercel',
      logo: 'https://assets.composio.dev/icons/vercel.svg',
      description:
          'Inspect deployments, manage project environments, and trigger builds.',
      category: 'Developer Tools',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'gitlab',
      name: 'GitLab',
      logo: 'https://assets.composio.dev/icons/gitlab.svg',
      description:
          'Manage GitLab repositories, merge requests, CI/CD pipelines, and issues.',
      category: 'Developer Tools',
      toolCount: 30,
    ),
    ComposioToolkit(
      slug: 'airtable',
      name: 'Airtable',
      logo: 'https://assets.composio.dev/icons/airtable.svg',
      description:
          'Read and update records in relational Airtable spreadsheets and bases.',
      category: 'Productivity',
      toolCount: 24,
    ),
    ComposioToolkit(
      slug: 'asana',
      name: 'Asana',
      logo: 'https://assets.composio.dev/icons/asana.svg',
      description:
          'Create tasks, assign deadlines, organize project boards, and tag milestones.',
      category: 'Productivity',
      toolCount: 26,
    ),
    ComposioToolkit(
      slug: 'zoom',
      name: 'Zoom',
      logo: 'https://assets.composio.dev/icons/zoom.svg',
      description:
          'Schedule video conferences, retrieve recordings, and generate meeting links.',
      category: 'Communication',
      toolCount: 16,
    ),
    ComposioToolkit(
      slug: 'clickup',
      name: 'ClickUp',
      logo: 'https://assets.composio.dev/icons/clickup.svg',
      description:
          'Track team goals, custom task fields, checklists, and sprint documents.',
      category: 'Productivity',
      toolCount: 28,
    ),
    ComposioToolkit(
      slug: 'zendesk',
      name: 'Zendesk',
      logo: 'https://assets.composio.dev/icons/zendesk.svg',
      description:
          'Manage customer support tickets, satisfaction ratings, and knowledgebase.',
      category: 'CRM',
      toolCount: 22,
    ),
    ComposioToolkit(
      slug: 'reddit',
      name: 'Reddit',
      logo: 'https://assets.composio.dev/icons/reddit.svg',
      description:
          'Search subreddits, read post discussions, and retrieve trending topics.',
      category: 'Social',
      toolCount: 15,
    ),
    ComposioToolkit(
      slug: 'spotify',
      name: 'Spotify',
      logo: 'https://assets.composio.dev/icons/spotify.svg',
      description:
          'Control playback, search tracks, query playlists, and get user history.',
      category: 'Media',
      toolCount: 18,
    ),
    ComposioToolkit(
      slug: 'youtube',
      name: 'YouTube',
      logo: 'https://assets.composio.dev/icons/youtube.svg',
      description:
          'Search videos, fetch comments, view video details, and manage playlists.',
      category: 'Media',
      toolCount: 20,
    ),
    ComposioToolkit(
      slug: 'figma',
      name: 'Figma',
      logo: 'https://assets.composio.dev/icons/figma.svg',
      description:
          'Inspect design components, extract styles, and get design comments.',
      category: 'Design',
      toolCount: 16,
    ),
  ];
}
