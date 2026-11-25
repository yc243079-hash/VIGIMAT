import 'package:flutter/material.dart';
import 'vigimat_colors.dart';

/// Logo vectoriel officiel VIGIMAT
/// Conçu pour être ultra-net à toute échelle (de 24px à 512px).
class VigimatLogo extends StatelessWidget {
  const VigimatLogo({
    super.key,
    this.size = 56,
    this.showWordmark = false,
    this.subtitle,
    this.onDark = false,
  });

  final double size;
  final bool showWordmark;
  final String? subtitle;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VigimatLogoPainter(onDark: onDark),
      ),
    );

    if (!showWordmark) return mark;

    final primaryText = onDark ? Colors.white : VigimatColors.navy;
    final secondaryText = onDark
        ? Colors.white.withValues(alpha: 0.65)
        : VigimatColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        SizedBox(width: size * 0.25),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VIGIMAT',
              style: TextStyle(
                color: primaryText,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                height: 1.0,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: size * 0.08),
              Text(
                subtitle!.toUpperCase(),
                style: TextStyle(
                  color: secondaryText,
                  fontSize: size * 0.17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _VigimatLogoPainter extends CustomPainter {
  const _VigimatLogoPainter({required this.onDark});

  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Fond du Bouclier Hexagonal Tactique
    final shieldPath = Path();
    // Forme de bouclier militaire profilé
    shieldPath.moveTo(w * 0.50, h * 0.04); // Sommet
    shieldPath.lineTo(w * 0.90, h * 0.20); // Épaule droite
    shieldPath.lineTo(w * 0.88, h * 0.62); // Flanc droit
    shieldPath.lineTo(w * 0.50, h * 0.96); // Pointe inférieure
    shieldPath.lineTo(w * 0.12, h * 0.62); // Flanc gauche
    shieldPath.lineTo(w * 0.10, h * 0.20); // Épaule gauche
    shieldPath.close();

    // Gradient du bouclier
    final shieldPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: onDark
            ? [
                const Color(0xFF1B3B60),
                const Color(0xFF0F2644),
                const Color(0xFF08182D),
              ]
            : [
                const Color(0xFF132F52),
                const Color(0xFF0E233E),
                const Color(0xFF09172A),
              ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Ombre portée subtile du bouclier
    canvas.drawShadow(
      shieldPath,
      onDark ? VigimatColors.emeraldGlow : VigimatColors.navy.withValues(alpha: 0.25),
      w * 0.08,
      false,
    );
    canvas.drawPath(shieldPath, shieldPaint);

    // Bordure biseautée du bouclier (armure tactique)
    final borderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: onDark ? 0.45 : 0.25),
          VigimatColors.turquoise.withValues(alpha: 0.7),
          VigimatColors.emerald.withValues(alpha: 0.9),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.038
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(shieldPath, borderPaint);

    // 2. Le Grand "V" Aérodynamique & Tactique (Vigilance)
    final vPath = Path();
    vPath.moveTo(w * 0.24, h * 0.28);
    vPath.lineTo(w * 0.50, h * 0.76);
    vPath.lineTo(w * 0.76, h * 0.28);
    vPath.lineTo(w * 0.64, h * 0.28);
    vPath.lineTo(w * 0.50, h * 0.57);
    vPath.lineTo(w * 0.36, h * 0.28);
    vPath.close();

    final vPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white,
          Color(0xFFE2E8F0),
          VigimatColors.turquoise,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(vPath, vPaint);

    // 3. Clé mécanique / Chevron central de Maintenance
    final wrenchPath = Path();
    wrenchPath.moveTo(w * 0.50, h * 0.32);
    wrenchPath.lineTo(w * 0.58, h * 0.46);
    wrenchPath.lineTo(w * 0.50, h * 0.62);
    wrenchPath.lineTo(w * 0.42, h * 0.46);
    wrenchPath.close();

    final wrenchPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [VigimatColors.emerald, VigimatColors.turquoise],
      ).createShader(Rect.fromLTWH(w * 0.4, h * 0.3, w * 0.2, h * 0.35));

    canvas.drawPath(wrenchPath, wrenchPaint);

    // 4. Balise d'état opérationnel centrale (Le point vert actif / radar)
    final dotPaint = Paint()..color = const Color(0xFF34D399);
    canvas.drawCircle(Offset(w * 0.50, h * 0.46), w * 0.045, dotPaint);

    // 5. Trinité discrète Mali (Vert, Or, Rouge) sur le bandeau supérieur
    final barW = w * 0.055;
    final barH = w * 0.024;
    final barY = h * 0.13;
    final barRadius = Radius.circular(w * 0.012);

    final greenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.40, barY, barW, barH),
      barRadius,
    );
    final goldRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.47, barY, barW, barH),
      barRadius,
    );
    final redRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.54, barY, barW, barH),
      barRadius,
    );

    canvas.drawRRect(greenRect, Paint()..color = const Color(0xFF14B53A));
    canvas.drawRRect(goldRect, Paint()..color = const Color(0xFFFCD116));
    canvas.drawRRect(redRect, Paint()..color = const Color(0xFFCE1126));
  }

  @override
  bool shouldRepaint(covariant _VigimatLogoPainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}
