import 'package:flutter/material.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';

enum GrokMode { ask, imagine, build }

/// Top Mode Selector: Ask | Imagine | Build with an animated indicator line.
class GrokModeSelector extends StatelessWidget {
  const GrokModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  final GrokMode currentMode;
  final ValueChanged<GrokMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTab(
          context: context,
          label: 'Ask',
          mode: GrokMode.ask,
          isDark: isDark,
        ),
        const SizedBox(width: 16),
        _buildTab(
          context: context,
          label: 'Imagine',
          mode: GrokMode.imagine,
          isDark: isDark,
        ),
        const SizedBox(width: 16),
        _buildTab(
          context: context,
          label: 'Build',
          mode: GrokMode.build,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildTab({
    required BuildContext context,
    required String label,
    required GrokMode mode,
    required bool isDark,
  }) {
    final isSelected = currentMode == mode;
    final activeColor = isDark ? Colors.white : Colors.black87;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.45);

    return InkWell(
      onTap: () {
        Haptics.light();
        onModeChanged(mode);
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected
                    ? AppFontWeights.emphasis
                    : AppFontWeights.regular,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // White indicator line for active tab
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 2.5,
            width: isSelected ? 18 : 0,
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
