import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/void_logo.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

class VoidCouncilSheet extends StatefulWidget {
  const VoidCouncilSheet({
    super.key,
    required this.onLaunchCouncilPrompt,
    this.initialTopic = '',
  });

  final ValueChanged<String> onLaunchCouncilPrompt;
  final String initialTopic;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onLaunchCouncilPrompt,
    String initialTopic = '',
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: VoidCouncilSheet(
              onLaunchCouncilPrompt: onLaunchCouncilPrompt,
              initialTopic: initialTopic,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: VoidCouncilSheet(
          onLaunchCouncilPrompt: onLaunchCouncilPrompt,
          initialTopic: initialTopic,
        ),
      ),
    );
  }

  @override
  State<VoidCouncilSheet> createState() => _VoidCouncilSheetState();
}

class _VoidCouncilSheetState extends State<VoidCouncilSheet> {
  late final TextEditingController _topicCtrl;
  String _selectedMode = 'Architecture & Code';
  final Set<String> _enabledSeats = {
    'Lead Architect',
    'Principal Implementer',
    'Red-Team Auditor',
    'Chair Synthesizer',
  };

  static const List<({String id, String subtitle, IconData icon})> _seats = [
    (
      id: 'Lead Architect',
      subtitle: 'Deconstructs system design, edge cases & scalability',
      icon: Lucide.Compass,
    ),
    (
      id: 'Principal Implementer',
      subtitle: 'Writes concrete, production-ready code & execution steps',
      icon: Lucide.Code,
    ),
    (
      id: 'Red-Team Auditor',
      subtitle: 'Challenges assumptions, security flaws & regressions',
      icon: Lucide.ShieldAlert,
    ),
    (
      id: 'Chair Synthesizer',
      subtitle: 'Resolves disagreements into a single master deliverable',
      icon: Lucide.Sparkles,
    ),
  ];

  static const List<String> _modes = [
    'Architecture & Code',
    'Strategic Debate',
    'Security & Bug Audit',
    'Deep Research Consensus',
  ];

  @override
  void initState() {
    super.initState();
    _topicCtrl = TextEditingController(text: widget.initialTopic);
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  void _launch() {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) return;
    Haptics.medium();

    final seatsList = _seats
        .where((s) => _enabledSeats.contains(s.id))
        .map((s) => '- **${s.id}**: ${s.subtitle}')
        .join('\n');

    final prompt =
        '''
### VOID Multi-Agent Council Session ($_selectedMode)

**Objective / Problem**:
$topic

**Active Council Seats**:
$seatsList

**Protocol**:
1. Run a structured multi-perspective deliberation where each active seat contributes its specialized analysis, concrete implementation, and critical review.
2. Have the **Red-Team Auditor** explicitly challenge any weak assumptions, edge cases, or bugs in the initial proposal.
3. Conclude with the **Chair Synthesizer's Final Master Solution** — complete, verified, and directly actionable.
''';

    Navigator.of(context).pop();
    widget.onLaunchCouncilPrompt(prompt.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final bg = context.overlaySurface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: isDesktop
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.6,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDesktop)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Row(
                children: [
                  const VoidLogo(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOID Multi-Agent Council',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Multi-persona deliberation, red-team critique & synthesis',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Lucide.X, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Deliberation Mode
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _modes.map((m) {
                    final selected = _selectedMode == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(m),
                        selected: selected,
                        selectedColor: isDark
                            ? const Color(0xFF27272A)
                            : cs.primaryContainer,
                        backgroundColor: isDark
                            ? const Color(0xFF18181B)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? AppFontWeights.semibold
                              : AppFontWeights.regular,
                          color: selected
                              ? (isDark
                                    ? const Color(0xFFF4F4F5)
                                    : cs.onPrimaryContainer)
                              : cs.onSurfaceVariant,
                        ),
                        onSelected: (_) {
                          Haptics.light();
                          setState(() => _selectedMode = m);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Council Seats
              Text(
                'Specialist Seats',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ..._seats.map((seat) {
                final active = _enabledSeats.contains(seat.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (active && _enabledSeats.length <= 2) return;
                      Haptics.light();
                      setState(() {
                        if (active) {
                          _enabledSeats.remove(seat.id);
                        } else {
                          _enabledSeats.add(seat.id);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? cs.primary.withValues(alpha: 0.10)
                            : (isDark
                                  ? const Color(0xFF18181B)
                                  : cs.surfaceContainerLow),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? cs.primary.withValues(alpha: 0.45)
                              : cs.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            seat.icon,
                            size: 17,
                            color: active ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  seat.id,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: AppFontWeights.emphasis,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  seat.subtitle,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            active ? Lucide.CheckCircle2 : Lucide.Circle,
                            size: 16,
                            color: active ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),

              IosFormTextField(
                label: 'Problem or Task for the Council',
                controller: _topicCtrl,
                hintText:
                    'Describe the architecture, feature, bug, or strategic decision...',
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _launch,
                  icon: const Icon(Lucide.Sparkles, size: 16),
                  label: Text(
                    'Convene Council (${_enabledSeats.length} Agents)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
