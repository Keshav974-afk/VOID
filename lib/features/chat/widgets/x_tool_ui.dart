import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/x_search/x_search_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Card displaying an X (Twitter) search result or thread.
class XToolUi extends StatelessWidget {
  const XToolUi({super.key, required this.result, this.textColor});

  final XSearchResult result;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (result.posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14171A) : const Color(0xFFF5F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2F3336) : const Color(0xFFE1E8ED),
          ),
        ),
        child: Row(
          children: [
            const Icon(Lucide.AtSign, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.summary ?? 'No X posts found.',
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
        for (int i = 0; i < result.posts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _XTweetCard(tweet: result.posts[i], isDark: isDark),
        ],
      ],
    );
  }
}

class _XTweetCard extends StatelessWidget {
  const _XTweetCard({required this.tweet, required this.isDark});

  final XTweet tweet;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bgColor = isDark ? const Color(0xFF0F1419) : const Color(0xFFF7F9F9);
    final borderColor = isDark
        ? const Color(0xFF2F3336)
        : const Color(0xFFCFD9DE);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Handle, Verified, X logo
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (tweet.avatarUrl != null && tweet.avatarUrl!.isNotEmpty)
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(tweet.avatarUrl!),
                  backgroundColor: cs.surfaceContainerHighest,
                )
              else
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Text(
                    tweet.author.isNotEmpty
                        ? tweet.author[0].toUpperCase()
                        : 'X',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.emphasis,
                      color: cs.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tweet.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: AppFontWeights.emphasis,
                            ),
                          ),
                        ),
                        if (tweet.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: Color(0xFF1D9BF0),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '@${tweet.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              // X badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: const Text(
                  '𝕏',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'sans-serif',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tweet Body
          Text(
            tweet.text,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),

          // Media preview if any
          if (tweet.media.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                tweet.media.first,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Footer: Metrics & Link
          Row(
            children: [
              if (tweet.metrics.reposts > 0) ...[
                const Icon(Lucide.Repeat, size: 13, color: Color(0xFF00BA7C)),
                const SizedBox(width: 4),
                Text(
                  _formatCount(tweet.metrics.reposts),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00BA7C),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (tweet.metrics.likes > 0) ...[
                const Icon(Lucide.Heart, size: 13, color: Color(0xFFF91880)),
                const SizedBox(width: 4),
                Text(
                  _formatCount(tweet.metrics.likes),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFF91880),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (tweet.metrics.views > 0) ...[
                Icon(
                  Lucide.Eye,
                  size: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatCount(tweet.metrics.views),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const Spacer(),
              if (tweet.url.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final uri = Uri.tryParse(tweet.url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View on 𝕏',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: AppFontWeights.medium,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Lucide.ExternalLink, size: 11, color: cs.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
