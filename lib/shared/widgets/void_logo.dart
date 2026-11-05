import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Flagship VOID Logo widget.
/// Renders a sharp, minimalist geometric singularity emblem.
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
    final accentColor = const Color(0xFFFF7A00); // Grok/VOID electric amber

    Widget emblem = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VoidEmblemPainter(
          primaryColor: primaryColor,
          accentColor: accentColor,
          glow: glow,
          grokStyle: grokStyle,
        ),
      ),
    );

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
  const _VoidEmblemPainter({
    required this.primaryColor,
    required this.accentColor,
    required this.glow,
    this.grokStyle = false,
  });

  final Color primaryColor;
  final Color accentColor;
  final bool glow;
  final bool grokStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    if (grokStyle) {
      // Paint the exact Grok / VOID slashed singularity ring
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.rotate(-math.pi / 4.8); // 37.5 degree tilt
      canvas.translate(-w / 2, -h / 2);

      final ringPath = Path();
      final rx = w * 0.36;
      final ry = h * 0.36;

      // Outer ellipse
      ringPath.addOval(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      );
      // Inner cut out
      final innerPath = Path()
        ..addOval(
          Rect.fromCenter(
            center: center,
            width: (rx - w * 0.13) * 2,
            height: (ry - h * 0.13) * 2,
          ),
        );

      final slashedRing = Path.combine(
        PathOperation.difference,
        ringPath,
        innerPath,
      );

      // Top right slash blade
      final topBlade = Path()
        ..moveTo(center.dx + rx * 0.85, center.dy - ry * 0.20)
        ..quadraticBezierTo(
          center.dx + rx * 1.55,
          center.dy - ry * 1.05,
          center.dx + rx * 1.85,
          center.dy - ry * 1.45,
        )
        ..quadraticBezierTo(
          center.dx + rx * 1.25,
          center.dy - ry * 0.95,
          center.dx + rx * 0.40,
          center.dy - ry * 0.90,
        )
        ..close();

      // Bottom left slash blade
      final bottomBlade = Path()
        ..moveTo(center.dx - rx * 0.85, center.dy + ry * 0.20)
        ..quadraticBezierTo(
          center.dx - rx * 1.55,
          center.dy + ry * 1.05,
          center.dx - rx * 1.85,
          center.dy + ry * 1.45,
        )
        ..quadraticBezierTo(
          center.dx - rx * 1.25,
          center.dy + ry * 0.95,
          center.dx - rx * 0.40,
          center.dy + ry * 0.90,
        )
        ..close();

      final fullSingularity = Path()
        ..addPath(slashedRing, Offset.zero)
        ..addPath(topBlade, Offset.zero)
        ..addPath(bottomBlade, Offset.zero);

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = primaryColor;

      if (glow) {
        final glowPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = primaryColor.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12);
        canvas.drawPath(fullSingularity, glowPaint);
      }

      canvas.drawPath(fullSingularity, fillPaint);
      canvas.restore();
      return;
    }

    final radius = w * 0.44;

    // 1. Subtle Outer Singularity Orbit / Ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..shader = SweepGradient(
        colors: [
          primaryColor.withValues(alpha: 0.15),
          primaryColor.withValues(alpha: 0.85),
          accentColor.withValues(alpha: 0.95),
          primaryColor.withValues(alpha: 0.15),
        ],
        stops: const [0.0, 0.45, 0.7, 1.0],
        transform: const GradientRotation(-math.pi / 4),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, ringPaint);

    // 2. Sharp Geometric "V" Singularity
    final vPath = Path();
    // Top-left outer
    vPath.moveTo(w * 0.22, h * 0.26);
    // Left shoulder
    vPath.lineTo(w * 0.38, h * 0.26);
    // Center bottom vertex
    vPath.lineTo(w * 0.50, h * 0.62);
    // Right shoulder
    vPath.lineTo(w * 0.62, h * 0.26);
    // Top-right outer
    vPath.lineTo(w * 0.78, h * 0.26);
    // Bottom apex
    vPath.lineTo(w * 0.54, h * 0.76);
    vPath.lineTo(w * 0.46, h * 0.76);
    vPath.close();

    final vPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primaryColor,
          primaryColor.withValues(alpha: 0.9),
          accentColor,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    if (glow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = primaryColor.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12);
      canvas.drawPath(vPath, glowPaint);
    }

    canvas.drawPath(vPath, vPaint);

    // 3. Central singularity core dot
    final corePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.50, h * 0.40), w * 0.05, corePaint);
  }

  @override
  bool shouldRepaint(covariant _VoidEmblemPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glow != glow ||
        oldDelegate.grokStyle != grokStyle;
  }
}
