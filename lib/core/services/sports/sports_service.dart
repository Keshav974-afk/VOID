import 'dart:convert';
import 'package:http/http.dart' as http;

/// Information about a single team in a sports match.
class SportsTeam {
  const SportsTeam({
    required this.name,
    required this.abbreviation,
    this.score,
    this.logoUrl,
    this.record,
  });

  final String name;
  final String abbreviation;
  final String? score;
  final String? logoUrl;
  final String? record;

  Map<String, dynamic> toJson() => {
    'name': name,
    'abbreviation': abbreviation,
    if (score != null) 'score': score,
    if (logoUrl != null) 'logo': logoUrl,
    if (record != null) 'record': record,
  };

  factory SportsTeam.fromJson(Map<String, dynamic> json) {
    return SportsTeam(
      name: (json['name'] ?? json['displayName'] ?? '').toString(),
      abbreviation: (json['abbreviation'] ?? json['shortDisplayName'] ?? '')
          .toString(),
      score: json['score']?.toString(),
      logoUrl: json['logo']?.toString(),
      record: json['record']?.toString(),
    );
  }
}

/// A sports matchup / game event.
class SportsGame {
  const SportsGame({
    required this.id,
    required this.name,
    required this.shortName,
    required this.status,
    required this.statusDetail,
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    this.isLive = false,
    this.isFinal = false,
    this.venue,
  });

  final String id;
  final String name;
  final String shortName;
  final String status;
  final String statusDetail;
  final String date;
  final SportsTeam homeTeam;
  final SportsTeam awayTeam;
  final bool isLive;
  final bool isFinal;
  final String? venue;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'status': status,
    'status_detail': statusDetail,
    'date': date,
    'is_live': isLive,
    'is_final': isFinal,
    if (venue != null) 'venue': venue,
    'home_team': homeTeam.toJson(),
    'away_team': awayTeam.toJson(),
  };

  factory SportsGame.fromJson(Map<String, dynamic> json) {
    return SportsGame(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      shortName: (json['short_name'] ?? json['shortName'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusDetail: (json['status_detail'] ?? json['statusDetail'] ?? '')
          .toString(),
      date: (json['date'] ?? '').toString(),
      isLive: json['is_live'] == true || json['isLive'] == true,
      isFinal: json['is_final'] == true || json['isFinal'] == true,
      venue: json['venue']?.toString(),
      homeTeam: json['home_team'] is Map
          ? SportsTeam.fromJson(
              Map<String, dynamic>.from(json['home_team'] as Map),
            )
          : const SportsTeam(name: '', abbreviation: ''),
      awayTeam: json['away_team'] is Map
          ? SportsTeam.fromJson(
              Map<String, dynamic>.from(json['away_team'] as Map),
            )
          : const SportsTeam(name: '', abbreviation: ''),
    );
  }
}

/// Result of a sports query.
class SportsToolResult {
  const SportsToolResult({
    required this.league,
    required this.games,
    this.summary,
    this.error,
  });

  final String league;
  final List<SportsGame> games;
  final String? summary;
  final String? error;

  bool get isSuccess => error == null;

  Map<String, dynamic> toJson() => {
    'league': league,
    'total': games.length,
    if (summary != null) 'summary': summary,
    if (error != null) 'error': error,
    'games': games.map((g) => g.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static SportsToolResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['games'] is! List) return null;
      final gameList = (map['games'] as List)
          .whereType<Map>()
          .map((e) => SportsGame.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return SportsToolResult(
        league: (map['league'] ?? '').toString(),
        games: gameList,
        summary: map['summary']?.toString(),
        error: map['error']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Service that retrieves live sports scores, schedules, and standings via ESPN public APIs.
class SportsService {
  SportsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Map<String, (String sport, String leagueCode)> _leagueMap = {
    'nba': ('basketball', 'nba'),
    'wnba': ('basketball', 'wnba'),
    'nfl': ('football', 'nfl'),
    'epl': ('soccer', 'eng.1'),
    'premier_league': ('soccer', 'eng.1'),
    'ucl': ('soccer', 'uefa.champions'),
    'champions_league': ('soccer', 'uefa.champions'),
    'laliga': ('soccer', 'esp.1'),
    'seriea': ('soccer', 'ita.1'),
    'bundesliga': ('soccer', 'ger.1'),
    'mls': ('soccer', 'usa.1'),
    'mlb': ('baseball', 'mlb'),
    'nhl': ('hockey', 'nhl'),
    'f1': ('racing', 'f1'),
  };

  Future<SportsToolResult> getScores({
    String league = 'nba',
    String? query,
    String view = 'scoreboard',
  }) async {
    final normKey = league.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final spec = _leagueMap[normKey] ?? ('basketball', 'nba');

    final endpoint =
        'https://site.api.espn.com/apis/site/v2/sports/${spec.$1}/${spec.$2}/scoreboard';

    try {
      final response = await _client
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return SportsToolResult(
          league: league,
          games: [],
          error: 'Sports service returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final events = (data['events'] as List?) ?? const <dynamic>[];
      final games = <SportsGame>[];

      for (final ev in events) {
        if (ev is! Map) continue;
        final id = (ev['id'] ?? '').toString();
        final name = (ev['name'] ?? '').toString();
        final shortName = (ev['shortName'] ?? name).toString();
        final date = (ev['date'] ?? '').toString();

        if (query != null && query.trim().isNotEmpty) {
          final q = query.toLowerCase();
          if (!name.toLowerCase().contains(q) &&
              !shortName.toLowerCase().contains(q)) {
            continue;
          }
        }

        final competitions = (ev['competitions'] as List?) ?? const <dynamic>[];
        if (competitions.isEmpty || competitions.first is! Map) continue;
        final comp = competitions.first as Map<String, dynamic>;

        final statusObj = comp['status'] as Map<String, dynamic>? ?? {};
        final statusType = statusObj['type'] as Map<String, dynamic>? ?? {};
        final statusName = (statusType['name'] ?? '').toString();
        final statusDetail =
            (statusType['shortDetail'] ?? statusType['detail'] ?? '')
                .toString();
        final isLive = statusName == 'STATUS_IN_PROGRESS';
        final isFinal = statusName == 'STATUS_FINAL';

        final venueObj = comp['venue'] as Map<String, dynamic>?;
        final venueName = venueObj?['fullName']?.toString();

        final competitors = (comp['competitors'] as List?) ?? const <dynamic>[];
        SportsTeam? home;
        SportsTeam? away;

        for (final c in competitors) {
          if (c is! Map) continue;
          final teamObj = c['team'] as Map<String, dynamic>? ?? {};
          final isHome = c['homeAway'] == 'home';
          final t = SportsTeam(
            name: (teamObj['displayName'] ?? teamObj['name'] ?? '').toString(),
            abbreviation: (teamObj['abbreviation'] ?? '').toString(),
            score: c['score']?.toString(),
            logoUrl: teamObj['logo']?.toString(),
            record: (c['records'] as List?)?.firstOrNull?['summary']
                ?.toString(),
          );
          if (isHome) {
            home = t;
          } else {
            away = t;
          }
        }

        if (home != null && away != null) {
          games.add(
            SportsGame(
              id: id,
              name: name,
              shortName: shortName,
              status: statusName,
              statusDetail: statusDetail,
              date: date,
              homeTeam: home,
              awayTeam: away,
              isLive: isLive,
              isFinal: isFinal,
              venue: venueName,
            ),
          );
        }
      }

      final leagueTitle =
          (data['leagues'] as List?)?.firstOrNull?['name']?.toString() ??
          league.toUpperCase();

      return SportsToolResult(
        league: leagueTitle,
        games: games,
        summary: games.isNotEmpty
            ? 'Retrieved ${games.length} games for $leagueTitle.'
            : 'No scheduled games found for $leagueTitle right now.',
      );
    } catch (e) {
      return SportsToolResult(
        league: league,
        games: [],
        error: 'Failed to retrieve sports data: $e',
      );
    }
  }
}
