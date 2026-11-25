import 'package:flutter/material.dart';

abstract final class VigimatColors {
  static const navy = Color(0xFF142B4A);
  static const turquoise = Color(0xFF14B8A6);
  static const background = Color(0xFFF4F6FA);
  static const muted = Color(0xFF687386);
  static const border = Color(0xFFE7EBF1);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF16A34A);

  // Fonds doux pour les badges et icônes de statut
  static const redSoft = Color(0xFFFEE2E2);
  static const orangeSoft = Color(0xFFFEF3C7);
  static const greenSoft = Color(0xFFDCFCE7);
  static const turquoiseSoft = Color(0xFFCCFBF1);
}

class VigimatLogoMark extends StatelessWidget {
  const VigimatLogoMark({super.key, this.size = 48, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.12)
            : VigimatColors.navy,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.settings_suggest_rounded,
            size: size * 0.63,
            color: Colors.white,
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.12,
            child: Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: BoxDecoration(
                color: VigimatColors.turquoise,
                shape: BoxShape.circle,
                border: Border.all(
                  color: onDark ? VigimatColors.navy : Colors.white,
                  width: size * 0.035,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VigimatWordmark extends StatelessWidget {
  const VigimatWordmark({
    super.key,
    this.markSize = 42,
    this.onDark = false,
    this.showSubtitle = false,
  });

  final double markSize;
  final bool onDark;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark ? Colors.white : VigimatColors.navy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VigimatLogoMark(size: markSize, onDark: onDark),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VIGIMAT',
              style: TextStyle(
                color: foreground,
                fontSize: markSize * 0.38,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.35,
                height: 1.05,
              ),
            ),
            if (showSubtitle) ...[
              const SizedBox(height: 4),
              Text(
                'MAINTENANCE & SUIVI',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.68),
                  fontSize: markSize * 0.19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class VigimatPageHeader extends StatelessWidget {
  const VigimatPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [VigimatColors.navy, Color(0xFF1B4266)],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: VigimatColors.navy.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: VigimatColors.turquoise, size: 23),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}
