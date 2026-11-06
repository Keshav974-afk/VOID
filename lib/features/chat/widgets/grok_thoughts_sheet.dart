import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

class GrokThoughtItem {
  final String title;
  final String? code;
  final String? output;
  final String language;
  final bool isSearch;
  final bool isCommand;
  final bool isThought;
  final List<String> searchQueries;

  GrokThoughtItem({
    required this.title,
    this.code,
    this.output,
    this.language = 'Bash',
    this.isSearch = false,
    this.isCommand = false,
    this.isThought = false,
    this.searchQueries = const <String>[],
  });
}

sealed class GrokTimelineStepItem {
  const GrokTimelineStepItem();
}

class GrokSearchesStepItem extends GrokTimelineStepItem {
  final int count;
  final List<String> queries;
  const GrokSearchesStepItem({required this.count, required this.queries});
}

class GrokCommandStepItem extends GrokTimelineStepItem {
  final String title;
  final String? code;
  final String? output;
  final String language;
  const GrokCommandStepItem({
    required this.title,
    this.code,
    this.output,
    this.language = 'Bash',
  });
}

class GrokThoughtStepItem extends GrokTimelineStepItem {
  final String title;
  final List<String> extraBullets;
  const GrokThoughtStepItem({
    required this.title,
    this.extraBullets = const <String>[],
  });
}

class GrokWorkTimelineWidget extends StatelessWidget {
  const GrokWorkTimelineWidget({
    super.key,
    this.orderedSteps,
    this.searchesCount = 0,
    this.searchQueries = const <String>[],
    this.items = const <GrokThoughtItem>[],
    this.thoughtBullets = const <String>[],
  });

  final List<GrokTimelineStepItem>? orderedSteps;
  final int searchesCount;
  final List<String> searchQueries;
  final List<GrokThoughtItem> items;
  final List<String> thoughtBullets;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? const Color(0xFF2C2D31)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18);

    final effectiveSteps = <GrokTimelineStepItem>[];

    if (orderedSteps != null && orderedSteps!.isNotEmpty) {
      effectiveSteps.addAll(orderedSteps!);
    } else {
      if (searchesCount > 0) {
        effectiveSteps.add(
          GrokSearchesStepItem(count: searchesCount, queries: searchQueries),
        );
      }
      for (final item in items) {
        if (item.isCommand || item.code != null) {
          effectiveSteps.add(
            GrokCommandStepItem(
              title: item.title,
              code: item.code,
              output: item.output,
              language: item.language,
            ),
          );
        }
      }
      if (thoughtBullets.isNotEmpty) {
        effectiveSteps.add(
          GrokThoughtStepItem(
            title: thoughtBullets.first,
            extraBullets: thoughtBullets.skip(1).toList(),
          ),
        );
      }
    }

    if (effectiveSteps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < effectiveSteps.length; i++) ...[
            switch (effectiveSteps[i]) {
              GrokSearchesStepItem s => _SearchTimelineStepRow(
                key: ValueKey('search_$i'),
                count: s.count,
                queries: s.queries,
                isFirst: i == 0,
                isLast: i == effectiveSteps.length - 1,
                lineColor: lineColor,
              ),
              GrokCommandStepItem c => _CommandTimelineStepRow(
                key: ValueKey('command_$i'),
                item: c,
                isFirst: i == 0,
                isLast: i == effectiveSteps.length - 1,
                lineColor: lineColor,
              ),
              GrokThoughtStepItem t => _ThoughtTimelineStepRow(
                key: ValueKey('thought_$i'),
                title: t.title,
                extraBullets: t.extraBullets,
                isFirst: i == 0,
                isLast: i == effectiveSteps.length - 1,
                lineColor: lineColor,
              ),
            },
          ],
        ],
      ),
    );
  }
}

class _SearchTimelineStepRow extends StatefulWidget {
  const _SearchTimelineStepRow({
    super.key,
    required this.count,
    required this.queries,
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
  });

  final int count;
  final List<String> queries;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  State<_SearchTimelineStepRow> createState() => _SearchTimelineStepRowState();
}

class _SearchTimelineStepRowState extends State<_SearchTimelineStepRow> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF6B7280);
    final titleColor = isDark
        ? const Color(0xFFD4D4D8)
        : const Color(0xFF1F2937);
    final globeColor = isDark
        ? const Color(0xFF75777B)
        : const Color(0xFF9CA3AF);
    final queryTextColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF4B5563);

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: CustomPaint(
            painter: _TimelineStepLinePainter(
              isFirst: widget.isFirst,
              isLast: widget.isLast,
              lineColor: widget.lineColor,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(Lucide.Search, size: 15, color: iconColor),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (widget.queries.isNotEmpty) {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Ran ${widget.count} search${widget.count > 1 ? 'es' : ''}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: AppFontWeights.medium,
                        color: titleColor,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isExpanded && widget.queries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final query in widget.queries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2.5,
                                  right: 8,
                                ),
                                child: Icon(
                                  Lucide.Globe,
                                  size: 13,
                                  color: globeColor,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  query.startsWith('Searched web for ')
                                      ? query
                                      : 'Searched web for $query',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: queryTextColor,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommandTimelineStepRow extends StatefulWidget {
  const _CommandTimelineStepRow({
    super.key,
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
  });

  final GrokCommandStepItem item;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  State<_CommandTimelineStepRow> createState() =>
      _CommandTimelineStepRowState();
}

class _CommandTimelineStepRowState extends State<_CommandTimelineStepRow> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF6B7280);
    final prefixColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF6B7280);
    final titleBlue = isDark
        ? const Color(0xFF8EAEC4)
        : const Color(0xFF2563EB);

    final titleText = widget.item.title.startsWith('Ran command ')
        ? widget.item.title.substring('Ran command '.length)
        : (widget.item.title.startsWith('Ran command')
              ? widget.item.title.substring('Ran command'.length).trim()
              : widget.item.title);

    final hasContent =
        (widget.item.code != null && widget.item.code!.isNotEmpty) ||
        (widget.item.output != null && widget.item.output!.isNotEmpty);

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: CustomPaint(
            painter: _TimelineStepLinePainter(
              isFirst: widget.isFirst,
              isLast: widget.isLast,
              lineColor: widget.lineColor,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    Lucide.SquareTerminal,
                    size: 15,
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                cursor: hasContent
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (hasContent) {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    }
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 24),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RichText(
                        softWrap: true,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Ran command ',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: prefixColor,
                              ),
                            ),
                            TextSpan(
                              text: titleText,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: AppFontWeights.medium,
                                color: titleBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isExpanded && hasContent)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131416),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF26282C),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.item.code != null &&
                            widget.item.code!.isNotEmpty)
                          SelectableText(
                            widget.item.code!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: Color(0xFFE5A46C),
                              height: 1.45,
                            ),
                          ),
                        if (widget.item.output != null &&
                            widget.item.output!.isNotEmpty) ...[
                          if (widget.item.code != null &&
                              widget.item.code!.isNotEmpty)
                            const SizedBox(height: 8),
                          SelectableText(
                            widget.item.output!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.0,
                              color: Color(0xFFABB2BF),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThoughtTimelineStepRow extends StatelessWidget {
  const _ThoughtTimelineStepRow({
    super.key,
    required this.title,
    this.extraBullets = const <String>[],
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
  });

  final String title;
  final List<String> extraBullets;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF6B7280);
    final titleBlue = isDark
        ? const Color(0xFF8EAEC4)
        : const Color(0xFF2563EB);
    final bulletColor = isDark
        ? const Color(0xFF8E9094)
        : const Color(0xFF4B5563);

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: CustomPaint(
            painter: _TimelineStepLinePainter(
              isFirst: isFirst,
              isLast: isLast,
              lineColor: lineColor,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(Lucide.Lightbulb, size: 15, color: iconColor),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    title,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: AppFontWeights.medium,
                      color: titleBlue,
                    ),
                  ),
                ),
              ),
              if (extraBullets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final bullet in extraBullets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 6,
                                  right: 8,
                                  left: 4,
                                ),
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: bulletColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  bullet,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: bulletColor,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineStepLinePainter extends CustomPainter {
  const _TimelineStepLinePainter({
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
  });

  final bool isFirst;
  final bool isLast;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    const iconTop = 4.0;
    const iconBottom = 20.0;

    if (!isFirst) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, iconTop), paint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(cx, iconBottom), Offset(cx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineStepLinePainter oldDelegate) {
    return isFirst != oldDelegate.isFirst ||
        isLast != oldDelegate.isLast ||
        lineColor != oldDelegate.lineColor;
  }
}

class GrokWorkBadge extends StatelessWidget {
  const GrokWorkBadge({
    super.key,
    required this.durationSeconds,
    this.isLoading = false,
    this.isExpanded = false,
    required this.onTap,
  });

  final int durationSeconds;
  final bool isLoading;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final text = isLoading
        ? 'Working...'
        : 'Worked for ${durationSeconds > 0 ? durationSeconds : 1}s';

    final textColor = isDark
        ? const Color(0xFFC0C2C8)
        : cs.onSurface.withValues(alpha: 0.75);
    final chevronColor = isDark
        ? const Color(0xFF8E9094)
        : cs.onSurface.withValues(alpha: 0.50);

    return SelectionContainer.disabled(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.medium,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Lucide.ChevronDown : Lucide.ChevronRight,
                  size: 14,
                  color: chevronColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GrokThoughtBadge extends StatelessWidget {
  const GrokThoughtBadge({
    super.key,
    required this.durationSeconds,
    this.isLoading = false,
    this.isExpanded = false,
    this.showIcon = false,
    required this.onTap,
  });

  final int durationSeconds;
  final bool isLoading;
  final bool isExpanded;
  final bool showIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final text = isLoading
        ? 'Thinking...'
        : 'Thought for ${durationSeconds > 0 ? durationSeconds : 1}s';

    final textColor = isDark
        ? const Color(0xFFC0C2C8)
        : cs.onSurface.withValues(alpha: 0.75);
    final iconColor = isDark
        ? const Color(0xFF8E9094)
        : cs.onSurface.withValues(alpha: 0.60);

    return SelectionContainer.disabled(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) ...[
                  Icon(Lucide.Lightbulb, size: 15, color: iconColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.medium,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Lucide.ChevronDown : Lucide.ChevronRight,
                  size: 14,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GrokThoughtsSheet extends StatelessWidget {
  const GrokThoughtsSheet({
    super.key,
    required this.durationSeconds,
    required this.searchesCount,
    this.searchQueries = const <String>[],
    required this.commandsCount,
    required this.items,
    required this.thoughtBullets,
  });

  final int durationSeconds;
  final int searchesCount;
  final List<String> searchQueries;
  final int commandsCount;
  final List<GrokThoughtItem> items;
  final List<String> thoughtBullets;

  static Future<void> show(
    BuildContext context, {
    required int durationSeconds,
    required int searchesCount,
    List<String> searchQueries = const <String>[],
    required int commandsCount,
    required List<GrokThoughtItem> items,
    required List<String> thoughtBullets,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => GrokThoughtsSheet(
        durationSeconds: durationSeconds,
        searchesCount: searchesCount,
        searchQueries: searchQueries,
        commandsCount: commandsCount,
        items: items,
        thoughtBullets: thoughtBullets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Thoughts & Work',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    GrokWorkTimelineWidget(
                      searchesCount: searchesCount,
                      searchQueries: searchQueries,
                      items: items,
                      thoughtBullets: thoughtBullets,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
