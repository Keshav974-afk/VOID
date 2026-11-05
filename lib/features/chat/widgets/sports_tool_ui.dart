import 'package:flutter/material.dart';

import '../../../core/services/sports/sports_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Card displaying live sports scores, schedules, and standings.
class SportsToolUi extends StatelessWidget {
  const SportsToolUi({super.key, required this.result, this.textColor});

  final SportsToolResult result;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (result.games.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16181D) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2E323B) : const Color(0xFFE2E4E8),
          ),
        ),
        child: Row(
          children: [
            const Icon(Lucide.Trophy, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.summary ?? 'No games found for ${result.league}.',
                style: TextStyle(
                  fontSize: 13,
                  color: textColor ?? cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(Lucide.Trophy, size: 14),
              const SizedBox(width: 6),
              Text(
                result.league,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppFontWeights.emphasis,
                ),
              ),
              const Spacer(),
              Text(
                '${result.games.length} games',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        for (int i = 0; i < result.games.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _SportsGameCard(game: result.games[i], isDark: isDark),
        ],
      ],
    );
  }
}

class _SportsGameCard extends StatelessWidget {
  const _SportsGameCard({required this.game, required this.isDark});

  final SportsGame game;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isDark ? const Color(0xFF14171E) : const Color(0xFFF7F8FA);
    final borderColor = isDark
        ? const Color(0xFF282D37)
        : const Color(0xFFE2E5EB);

    final isLive = game.isLive;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive ? const Color(0xFFEF4444) : borderColor,
          width: isLive ? 1.2 : 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          // Status bar: Live tag / Scheduled time / Final
          Row(
            children: [
              if (isLive) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: AppFontWeights.emphasis,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                game.statusDetail.isNotEmpty
                    ? game.statusDetail
                    : (game.isFinal ? 'Final' : 'Scheduled'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isLive
                      ? AppFontWeights.emphasis
                      : AppFontWeights.medium,
                  color: isLive ? const Color(0xFFEF4444) : cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (game.venue != null && game.venue!.isNotEmpty)
                Text(
                  game.venue!,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Away Team Row
          _TeamScoreRow(
            team: game.awayTeam,
            isWinner:
                game.isFinal &&
                _isScoreHigher(game.awayTeam.score, game.homeTeam.score),
            showScore: game.isLive || game.isFinal,
          ),
          const SizedBox(height: 6),

          // Home Team Row
          _TeamScoreRow(
            team: game.homeTeam,
            isWinner:
                game.isFinal &&
                _isScoreHigher(game.homeTeam.score, game.awayTeam.score),
            showScore: game.isLive || game.isFinal,
          ),
        ],
      ),
    );
  }

  static bool _isScoreHigher(String? s1, String? s2) {
    if (s1 == null || s2 == null) return false;
    final n1 = int.tryParse(s1) ?? 0;
    final n2 = int.tryParse(s2) ?? 0;
    return n1 > n2;
  }
}

class _TeamScoreRow extends StatelessWidget {
  const _TeamScoreRow({
    required this.team,
    required this.isWinner,
    required this.showScore,
  });

  final SportsTeam team;
  final bool isWinner;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        if (team.logoUrl != null && team.logoUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              team.logoUrl!,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Lucide.Trophy, size: 18),
            ),
          )
        else
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              team.abbreviation.isNotEmpty
                  ? team.abbreviation.substring(0, 1)
                  : '',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isWinner
                      ? AppFontWeights.emphasis
                      : AppFontWeights.medium,
                ),
              ),
              if (team.record != null && team.record!.isNotEmpty)
                Text(
                  team.record!,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
        if (showScore && team.score != null) ...[
          const SizedBox(width: 8),
          Text(
            team.score!,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isWinner
                  ? AppFontWeights.emphasis
                  : AppFontWeights.medium,
              color: isWinner ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
