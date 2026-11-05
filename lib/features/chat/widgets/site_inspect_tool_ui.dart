import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/inspect/site_inspection_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Interactive UI Card for Site Inspection & Bug Hunter results.
class SiteInspectToolUi extends StatefulWidget {
  const SiteInspectToolUi({super.key, required this.result, this.textColor});

  final SiteInspectToolResult result;
  final Color? textColor;

  @override
  State<SiteInspectToolUi> createState() => _SiteInspectToolUiState();
}

class _SiteInspectToolUiState extends State<SiteInspectToolUi> {
  bool _expanded = true;
  String _filter = 'all'; // 'all', 'critical', 'warning', 'a11y', 'security'

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF2EA043);
      case 'B':
        return const Color(0xFF3FB950);
      case 'C':
        return const Color(0xFFD29922);
      case 'D':
        return const Color(0xFFDB6D28);
      default:
        return const Color(0xFFF85149);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = widget.result;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F141C) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF2D333B)
        : const Color(0xFFD0D7DE);
    final gradeColor = _getGradeColor(res.grade);

    final filteredIssues = res.issues.where((i) {
      if (_filter == 'critical') return i.severity == 'critical';
      if (_filter == 'warning') return i.severity == 'warning';
      if (_filter == 'a11y') return i.category == 'accessibility';
      if (_filter == 'security') return i.category == 'security';
      return true;
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161C26) : const Color(0xFFEEF2F6),
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Lucide.Bug, size: 16, color: Color(0xFF58A6FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final uri = Uri.tryParse(res.url);
                      if (uri != null) launchUrl(uri);
                    },
                    child: Text(
                      res.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: AppFontWeights.emphasis,
                        color: const Color(0xFF58A6FF),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Health Score & Grade
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: gradeColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${res.healthScore}/100',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: AppFontWeights.emphasis,
                          color: gradeColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${res.grade})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: AppFontWeights.heavy,
                          color: gradeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Metrics Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildStatPill(
                  label: 'Latency',
                  value: '${res.latencyMs}ms',
                  isDark: isDark,
                ),
                _buildStatPill(
                  label: 'Status',
                  value: '${res.statusCode}',
                  isDark: isDark,
                  color: res.statusCode == 200
                      ? const Color(0xFF3FB950)
                      : const Color(0xFFF85149),
                ),
                _buildStatPill(
                  label: 'Critical',
                  value: '${res.criticalCount}',
                  isDark: isDark,
                  color: res.criticalCount > 0 ? const Color(0xFFF85149) : null,
                ),
                _buildStatPill(
                  label: 'Warnings',
                  value: '${res.warningCount}',
                  isDark: isDark,
                  color: res.warningCount > 0 ? const Color(0xFFD29922) : null,
                ),
                _buildStatPill(
                  label: 'Total Issues',
                  value: '${res.issues.length}',
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Issues list
          if (_expanded) ...[
            if (res.issues.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Lucide.CheckCircle,
                      size: 16,
                      color: Color(0xFF3FB950),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No bugs or security flaws detected on this page.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const Divider(height: 1),
              // Category filter pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    _buildFilterChip(
                      'All (${res.issues.length})',
                      'all',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Critical (${res.criticalCount})',
                      'critical',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Warnings (${res.warningCount})',
                      'warning',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip('Accessibility', 'a11y', isDark),
                    const SizedBox(width: 6),
                    _buildFilterChip('Security', 'security', isDark),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredIssues.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final issue = filteredIssues[index];
                  return _buildIssueTile(issue, isDark);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required String value,
    required bool isDark,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF21262D) : const Color(0xFFEAECEF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: AppFontWeights.emphasis,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, bool isDark) {
    final active = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF58A6FF).withValues(alpha: 0.2)
              : isDark
              ? const Color(0xFF1E242E)
              : const Color(0xFFF0F3F6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFF58A6FF) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFF58A6FF) : null,
            fontWeight: active
                ? AppFontWeights.emphasis
                : AppFontWeights.regular,
          ),
        ),
      ),
    );
  }

  Widget _buildIssueTile(SiteIssue issue, bool isDark) {
    final isCritical = issue.severity == 'critical';
    final isWarning = issue.severity == 'warning';

    final badgeColor = isCritical
        ? const Color(0xFFF85149)
        : isWarning
        ? const Color(0xFFD29922)
        : const Color(0xFF58A6FF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: badgeColor, width: 0.8),
                ),
                child: Text(
                  issue.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: AppFontWeights.heavy,
                    color: badgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF21262D)
                      : const Color(0xFFE1E4E8),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  issue.category,
                  style: const TextStyle(fontSize: 9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: AppFontWeights.emphasis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            issue.description,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
            ),
          ),
          if (issue.selector != null && issue.selector!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFEAECEF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Selector: ${issue.selector}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Color(0xFF58A6FF),
                ),
              ),
            ),
          ],
          if (issue.fixRecommendation != null &&
              issue.fixRecommendation!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Lucide.Lightbulb,
                  size: 12,
                  color: Color(0xFF3FB950),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Fix: ${issue.fixRecommendation}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF3FB950),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
