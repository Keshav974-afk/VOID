import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Flagship VOID Logo widget.
/// Renders the signature VOID "V" emblem with orbital ring and star.
class VoidLogo extends StatelessWidget {
  const VoidLogo({
    super.key,
    this.size = 24.0,
    this.withContainer = false,
    this.glow = false,
    this.grokStyle = false,
    this.color,
  });

  final double size;
  final bool withContainer;
  final bool glow;
  final bool grokStyle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor =
        color ?? (isDark ? Colors.white : const Color(0xFF0F1419));
    final tintColor = color ?? (isDark ? null : const Color(0xFF0F1419));

    Widget emblem = SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/icons/void_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        color: tintColor,
        colorBlendMode: tintColor != null ? BlendMode.srcIn : null,
        errorBuilder: (_, __, ___) => CustomPaint(
          size: Size.square(size),
          painter: _VoidEmblemPainter(primaryColor: primaryColor, glow: glow),
        ),
      ),
    );

    if (glow && !withContainer) {
      emblem = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: isDark ? 0.14 : 0.06),
              blurRadius: size * 0.35,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
        child: emblem,
      );
    }

    if (!withContainer) return emblem;

    final containerBg = isDark
        ? const Color(0xFF0A0A0A)
        : const Color(0xFFF0F2F5);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      width: size * 1.5,
      height: size * 1.5,
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(size * 0.35),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.08,
                  ),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(child: emblem),
    );
  }
}

class _VoidEmblemPainter extends CustomPainter {
  const _VoidEmblemPainter({required this.primaryColor, required this.glow});

  final Color primaryColor;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.50, h * 0.52);

    // 1. Tilted elliptical orbital ring around the V
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 11); // ~16 deg upward tilt to the right
    final orbitRect = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.78,
      height: h * 0.25,
    );
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round
      ..color = primaryColor.withValues(alpha: 0.88);
    if (glow) {
      final orbitGlow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..color = primaryColor.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04);
      canvas.drawArc(orbitRect, -0.35, math.pi * 1.65, false, orbitGlow);
    }
    canvas.drawArc(orbitRect, -0.35, math.pi * 1.65, false, orbitPaint);
    canvas.restore();

    // 2. Stylized 3D "V" with sliced right wing
    final vPath = Path()
      // Left wing outer top
      ..moveTo(w * 0.17, h * 0.24)
      // Left wing inner top (curved shoulder)
      ..lineTo(w * 0.34, h * 0.27)
      // Inner valley vertex
      ..lineTo(w * 0.50, h * 0.59)
      // Right wing inner climb
      ..lineTo(w * 0.62, h * 0.31)
      // Right wing curved top-right tip
      ..quadraticBezierTo(w * 0.68, h * 0.24, w * 0.84, h * 0.23)
      // Right outer edge descending to bottom apex
      ..lineTo(w * 0.52, h * 0.76)
      ..quadraticBezierTo(w * 0.50, h * 0.78, w * 0.48, h * 0.76)
      ..close();

    final vPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primaryColor;

    if (glow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = primaryColor.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.08);
      canvas.drawPath(vPath, glowPaint);
    }

    canvas.drawPath(vPath, vPaint);

    // 3. Four-point sparkle star on bottom-right under the orbital ring
    final starCenter = Offset(w * 0.71, h * 0.58);
    final starRadiusLong = w * 0.052;
    final starRadiusShort = w * 0.012;
    final starPath = Path()
      ..moveTo(starCenter.dx, starCenter.dy - starRadiusLong)
      ..quadraticBezierTo(
        starCenter.dx + starRadiusShort,
        starCenter.dy - starRadiusShort,
        starCenter.dx + starRadiusLong,
        starCenter.dy,
      )
      ..quadraticBezierTo(
        starCenter.dx + starRadiusShort,
        starCenter.dy + starRadiusShort,
        starCenter.dx,
        starCenter.dy + starRadiusLong,
      )
      ..quadraticBezierTo(
        starCenter.dx - starRadiusShort,
        starCenter.dy + starRadiusShort,
        starCenter.dx - starRadiusLong,
        starCenter.dy,
      )
      ..quadraticBezierTo(
        starCenter.dx - starRadiusShort,
        starCenter.dy - starRadiusShort,
        starCenter.dx,
        starCenter.dy - starRadiusLong,
      )
      ..close();

    canvas.drawPath(starPath, vPaint);
  }

  @override
  bool shouldRepaint(covariant _VoidEmblemPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor || oldDelegate.glow != glow;
  }
}
