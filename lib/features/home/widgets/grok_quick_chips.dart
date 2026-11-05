import 'package:flutter/material.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Horizontally scrollable quick-action chips floating above the input bar.
class GrokQuickChips extends StatelessWidget {
  const GrokQuickChips({super.key, required this.onSelectChip});

  final ValueChanged<String> onSelectChip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final chips = <_ChipItem>[
      const _ChipItem(id: 'videos', label: 'Videos', icon: Lucide.FileVideo),
      const _ChipItem(
        id: 'edit_image',
        label: 'Edit image',
        icon: Lucide.ImageDown,
      ),
      const _ChipItem(
        id: 'voice_mode',
        label: 'Voice Mode',
        icon: Lucide.Volume2,
      ),
      const _ChipItem(
        id: 'inspect_site',
        label: 'Inspect Site',
        icon: Lucide.Bug,
      ),
      const _ChipItem(
        id: 'sandbox_vps',
        label: 'Sandbox VPS',
        icon: Lucide.Terminal,
      ),
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = chips[index];
          return _buildChip(context: context, item: item, isDark: isDark);
        },
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required _ChipItem item,
    required bool isDark,
  }) {
    final bg = isDark ? const Color(0xFF1E242B) : const Color(0xFFEEF2F6);
    final border = isDark ? const Color(0xFF2C3440) : const Color(0xFFE2E8F0);
    final fg = isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87;

    return InkWell(
      onTap: () {
        Haptics.light();
        onSelectChip(item.id);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.medium,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipItem {
  const _ChipItem({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;
}
