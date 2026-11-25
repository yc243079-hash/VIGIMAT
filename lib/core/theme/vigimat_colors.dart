import 'package:flutter/material.dart';

/// Palette de couleurs tactique et moderne VIGIMAT
abstract final class VigimatColors {
  // --- Bleus tactiques profonds (Fondation & Surface) ---
  static const Color navyDarker = Color(0xFF071426); // Fond sombre ultime
  static const Color navy = Color(0xFF0F233D);       // Bleu nuit militaire principal
  static const Color navyLight = Color(0xFF1B3A60);  // Bleu nuit intermédiaire
  static const Color navyCard = Color(0xFF142B48);   // Surface carte mode sombre
  
  // --- Accents tactiques ---
  static const Color emerald = Color(0xFF10B981);     // Vert prêt / opérationnel (Mali green nod)
  static const Color emeraldDark = Color(0xFF059669);
  static const Color emeraldSoft = Color(0xFFD1FAE5);
  static const Color emeraldGlow = Color(0x3310B981);

  static const Color turquoise = Color(0xFF14B8A6);   // Cyan technique / HUD
  static const Color turquoiseSoft = Color(0xFFCCFBF1);

  static const Color gold = Color(0xFFF59E0B);        // Or / Alerte modérée / Attente (Mali gold nod)
  static const Color goldDark = Color(0xFFD97706);
  static const Color goldSoft = Color(0xFFFEF3C7);

  static const Color crimson = Color(0xFFEF4444);     // Rouge critique / Urgence (Mali red nod)
  static const Color crimsonDark = Color(0xFFDC2626);
  static const Color crimsonSoft = Color(0xFFFEE2E2);

  // --- Neutres & Surfaces Claires ---
  static const Color background = Color(0xFFF4F6FA);  // Fond clair moderne
  static const Color surface = Color(0xFFFFFFFF);     // Surface blanche pure
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  
  static const Color textPrimary = Color(0xFF0F172A);  // Slate 900 (ultra lisible)
  static const Color textSecondary = Color(0xFF475569);// Slate 600
  static const Color textMuted = Color(0xFF94A3B8);    // Slate 400
  static const Color muted = Color(0xFF94A3B8);        // Alias pour compatibilité
  static const Color textOnDark = Color(0xFFF8FAFC);   // Blanc cassé doux

  static const Color border = Color(0xFFE2E8F0);       // Bordure douce
  static const Color borderLight = Color(0xFFF1F5F9);  // Séparateur ultra fin
  static const Color borderFocus = Color(0xFF10B981);  // Focus anneau

  // --- Rôles & Badges Dédiés ---
  static const Color roleSoldier = Color(0xFF2563EB);    // Bleu soldat
  static const Color roleChief = Color(0xFF7C3AED);      // Violet / commandement chef
  static const Color roleTechnician = Color(0xFF0D9488); // Sarcelle technicien

  // --- Gradients Signature ---
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF061426), Color(0xFF0F2644), Color(0xFF0A1B30)],
  );

  static const LinearGradient cardDarkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF142C4B), Color(0xFF0E2036)],
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  static const LinearGradient chiefHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F233D), Color(0xFF1B355A)],
  );

  // --- Ombres Tactiles ---
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.02),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> glow(Color color, {double opacity = 0.25}) => [
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: 16,
      spreadRadius: 1,
      offset: const Offset(0, 4),
    ),
  ];
}
