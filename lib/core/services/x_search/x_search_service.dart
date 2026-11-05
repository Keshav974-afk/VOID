import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents engagement metrics for an X (Twitter) post.
class XTweetMetrics {
  const XTweetMetrics({
    this.likes = 0,
    this.reposts = 0,
    this.replies = 0,
    this.views = 0,
  });

  final int likes;
  final int reposts;
  final int replies;
  final int views;

  Map<String, dynamic> toJson() => {
    'likes': likes,
    'reposts': reposts,
    'replies': replies,
    'views': views,
  };

  factory XTweetMetrics.fromJson(Map<String, dynamic> json) {
    return XTweetMetrics(
      likes: (json['likes'] ?? json['favorite_count'] ?? 0) as int,
      reposts: (json['reposts'] ?? json['retweet_count'] ?? 0) as int,
      replies: (json['replies'] ?? json['reply_count'] ?? 0) as int,
      views: (json['views'] ?? 0) as int,
    );
  }
}

/// Represents an X (Twitter) post / tweet.
class XTweet {
  const XTweet({
    required this.id,
    required this.author,
    required this.username,
    required this.text,
    required this.url,
    this.avatarUrl,
    this.createdAt,
    this.metrics = const XTweetMetrics(),
    this.media = const <String>[],
    this.verified = false,
  });

  final String id;
  final String author;
  final String username;
  final String text;
  final String url;
  final String? avatarUrl;
  final String? createdAt;
  final XTweetMetrics metrics;
  final List<String> media;
  final bool verified;

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'username': username,
    'text': text,
    'url': url,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (createdAt != null) 'created_at': createdAt,
    'metrics': metrics.toJson(),
    if (media.isNotEmpty) 'media': media,
    'verified': verified,
  };

  factory XTweet.fromJson(Map<String, dynamic> json) {
    return XTweet(
      id: (json['id'] ?? '').toString(),
      author: (json['author'] ?? json['user']?['name'] ?? '').toString(),
      username: (json['username'] ?? json['user']?['screen_name'] ?? '')
          .toString()
          .replaceAll('@', ''),
      text: (json['text'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      avatarUrl:
          (json['avatar_url'] ?? json['user']?['profile_image_url_https'])
              ?.toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      metrics: json['metrics'] is Map
          ? XTweetMetrics.fromJson(
              Map<String, dynamic>.from(json['metrics'] as Map),
            )
          : const XTweetMetrics(),
      media: json['media'] is List
          ? List<String>.from((json['media'] as List).map((e) => e.toString()))
          : const <String>[],
      verified:
          json['verified'] == true || json['user']?['is_blue_verified'] == true,
    );
  }
}

/// Result of an X search or tweet retrieval operation.
class XSearchResult {
  const XSearchResult({
    required this.query,
    required this.action,
    required this.posts,
    this.summary,
    this.error,
  });

  final String query;
  final String action;
  final List<XTweet> posts;
  final String? summary;
  final String? error;

  bool get isSuccess => error == null;

  Map<String, dynamic> toJson() => {
    'query': query,
    'action': action,
    'total': posts.length,
    if (summary != null) 'summary': summary,
    if (error != null) 'error': error,
    'posts': posts.map((p) => p.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static XSearchResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['posts'] is! List) return null;
      final postsList = (map['posts'] as List)
          .whereType<Map>()
          .map((e) => XTweet.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return XSearchResult(
        query: (map['query'] ?? '').toString(),
        action: (map['action'] ?? 'search').toString(),
        posts: postsList,
        summary: map['summary']?.toString(),
        error: map['error']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Service that executes X/Twitter searches, fetches threads, and retrieves tweet details.
class XSearchService {
  XSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Main search/dispatch method for the `x_search` local tool.
  Future<XSearchResult> execute({
    required String query,
    String action = 'search',
    int limit = 5,
    String? xaiApiKey,
    String? xaiBaseUrl,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return const XSearchResult(
        query: '',
        action: 'search',
        posts: [],
        error: 'Query parameter cannot be empty.',
      );
    }

    try {
      // 1. If an xAI API key is provided, try the official xAI Grok search first
      if (xaiApiKey != null && xaiApiKey.trim().isNotEmpty) {
        try {
          final xaiResult = await _searchViaXai(
            query: cleanQuery,
            apiKey: xaiApiKey.trim(),
            baseUrl: xaiBaseUrl,
            limit: limit,
          );
          if (xaiResult != null && xaiResult.posts.isNotEmpty) {
            return xaiResult;
          }
        } catch (_) {
          // Fall through to public syndication / web-based retrieval
        }
      }

      // 2. Dispatch based on action
      switch (action.toLowerCase()) {
        case 'thread':
        case 'post_details':
          final tweetId = _extractTweetId(cleanQuery);
          if (tweetId != null) {
            final tweet = await _fetchTweetViaSyndication(tweetId);
            if (tweet != null) {
              return XSearchResult(
                query: cleanQuery,
                action: action,
                posts: [tweet],
                summary: 'Fetched post details from X.',
              );
            }
          }
          break;
        case 'user_posts':
          final username = cleanQuery.replaceAll('@', '').split(' ').first;
          final userResult = await _searchUserPosts(username, limit);
          if (userResult.posts.isNotEmpty) {
            return userResult;
          }
          break;
        case 'search':
        default:
          break;
      }

      // 3. Fallback search via web-based query
      return await _searchViaWeb(cleanQuery, limit: limit);
    } catch (e) {
      return XSearchResult(
        query: cleanQuery,
        action: action,
        posts: [],
        error: 'X search failed: $e',
      );
    }
  }

  /// Calls xAI endpoint with tool: x_search
  Future<XSearchResult?> _searchViaXai({
    required String query,
    required String apiKey,
    String? baseUrl,
    required int limit,
  }) async {
    final url = (baseUrl != null && baseUrl.isNotEmpty)
        ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/responses'
        : 'https://api.x.ai/v1/responses';

    final body = {
      'model': 'grok-3',
      'input': [
        {
          'role': 'system',
          'content':
              'You are a search assistant. Return real-time X posts relevant to the user query with URLs and quotes.',
        },
        {'role': 'user', 'content': query},
      ],
      'tools': [
        {'type': 'x_search'},
      ],
      'store': false,
      'stream': false,
    };

    final response = await _client
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final citations = (data['citations'] as List?) ?? const <dynamic>[];
    final posts = <XTweet>[];

    for (final cit in citations) {
      if (cit is! Map) continue;
      final cUrl = cit['url']?.toString() ?? '';
      if (!cUrl.contains('x.com') && !cUrl.contains('twitter.com')) continue;
      final tweetId = _extractTweetId(cUrl) ?? '${posts.length + 1}';
      final title = cit['title']?.toString() ?? 'X Post';
      final text =
          cit['snippet']?.toString() ?? cit['text']?.toString() ?? title;
      final handle = _extractHandleFromUrl(cUrl) ?? 'user';

      posts.add(
        XTweet(
          id: tweetId,
          author: handle,
          username: handle,
          text: text,
          url: cUrl,
        ),
      );
      if (posts.length >= limit) break;
    }

    if (posts.isNotEmpty) {
      return XSearchResult(
        query: query,
        action: 'search',
        posts: posts,
        summary: 'Retrieved ${posts.length} real-time posts from X.',
      );
    }
    return null;
  }

  /// Fetches a specific tweet by ID via Twitter's public syndication CDN.
  Future<XTweet?> _fetchTweetViaSyndication(String tweetId) async {
    try {
      final uri = Uri.parse(
        'https://cdn.syndication.twimg.com/tweet-result?id=$tweetId&lang=en',
      );
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>? ?? {};
      final photos = (data['photos'] as List?) ?? [];
      final mediaUrls = photos
          .whereType<Map>()
          .map((p) => p['url']?.toString())
          .whereType<String>()
          .toList();

      return XTweet(
        id: tweetId,
        author: (user['name'] ?? 'User').toString(),
        username: (user['screen_name'] ?? 'user').toString(),
        avatarUrl: user['profile_image_url_https']?.toString(),
        text: (data['text'] ?? '').toString(),
        url: 'https://x.com/${user['screen_name']}/status/$tweetId',
        createdAt: data['created_at']?.toString(),
        metrics: XTweetMetrics(
          likes: (data['favorite_count'] ?? 0) as int,
          reposts: (data['retweet_count'] ?? 0) as int,
          replies: (data['reply_count'] ?? 0) as int,
          views: (data['views']?['count'] ?? 0) as int,
        ),
        media: mediaUrls,
        verified: user['is_blue_verified'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Searches for posts by a specific user handle
  Future<XSearchResult> _searchUserPosts(String username, int limit) async {
    final searchQuery = 'from:$username';
    return _searchViaWeb(searchQuery, limit: limit);
  }

  /// Web-based search fallback targeting x.com / twitter.com
  Future<XSearchResult> _searchViaWeb(String query, {int limit = 5}) async {
    final searchUri = Uri.parse(
      'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent('site:x.com $query')}',
    );

    try {
      final response = await _client
          .get(
            searchUri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return XSearchResult(
          query: query,
          action: 'search',
          posts: [],
          error: 'Search engine returned HTTP ${response.statusCode}',
        );
      }

      final html = response.body;
      final posts = <XTweet>[];

      // Extract result-links and snippets from DuckDuckGo HTML
      final linkRegExp = RegExp(
        r'<a class="result__url"[^>]*href="([^"]+)"[^>]*>([^<]+)</a>',
      );
      final snippetRegExp = RegExp(
        r'<a class="result__snippet"[^>]*>([\s\S]*?)</a>',
      );

      final links = linkRegExp.allMatches(html).toList();
      final snippets = snippetRegExp.allMatches(html).toList();

      for (int i = 0; i < links.length && posts.length < limit; i++) {
        final rawUrl = links[i].group(1) ?? '';
        final unescapedUrl = Uri.decodeFull(rawUrl);
        // DuckDuckGo redirects through /l/?uddg=...
        final targetUrl = _extractActualUrl(unescapedUrl) ?? unescapedUrl;

        if (!targetUrl.contains('x.com') &&
            !targetUrl.contains('twitter.com')) {
          continue;
        }

        final tweetId = _extractTweetId(targetUrl);
        final snippetRaw = i < snippets.length
            ? snippets[i].group(1) ?? ''
            : '';
        final cleanSnippet = snippetRaw
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&#x27;', "'")
            .trim();

        final username = _extractHandleFromUrl(targetUrl) ?? 'X User';

        posts.add(
          XTweet(
            id: tweetId ?? 'post_${posts.length + 1}',
            author: username,
            username: username,
            text: cleanSnippet.isNotEmpty ? cleanSnippet : query,
            url: targetUrl,
          ),
        );
      }

      return XSearchResult(
        query: query,
        action: 'search',
        posts: posts,
        summary: posts.isNotEmpty
            ? 'Found ${posts.length} posts on X for "$query".'
            : 'No matching posts found on X.',
      );
    } catch (e) {
      return XSearchResult(
        query: query,
        action: 'search',
        posts: [],
        error: 'Web query failed: $e',
      );
    }
  }

  static String? _extractTweetId(String text) {
    final statusMatch = RegExp(r'/status/(\d+)').firstMatch(text);
    if (statusMatch != null) return statusMatch.group(1);
    if (RegExp(r'^\d+$').hasMatch(text.trim())) return text.trim();
    return null;
  }

  static String? _extractHandleFromUrl(String url) {
    final match = RegExp(
      r'(?:x|twitter)\.com/([^/?#]+)(?:/status)?',
    ).firstMatch(url);
    if (match != null) {
      final handle = match.group(1);
      if (handle != 'i' && handle != 'search' && handle != 'home') {
        return handle;
      }
    }
    return null;
  }

  static String? _extractActualUrl(String ddgUrl) {
    final uri = Uri.tryParse(ddgUrl);
    if (uri != null && uri.queryParameters.containsKey('uddg')) {
      return uri.queryParameters['uddg'];
    }
    return null;
  }
}
