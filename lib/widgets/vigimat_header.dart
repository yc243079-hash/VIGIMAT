import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';
import '../core/theme/vigimat_logo.dart';
import '../models/app_user_profile.dart';

class VigimatHeader extends StatelessWidget {
  const VigimatHeader({
    super.key,
    required this.profile,
    required this.title,
    this.subtitle,
    this.onRefresh,
    this.onProfileTap,
    this.trailing,
  });

  final AppUserProfile profile;
  final String title;
  final String? subtitle;
  final VoidCallback? onRefresh;
  final VoidCallback? onProfileTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (roleLabel, roleColor, roleBg) = switch (profile.role) {
      'unit_head' => ('Chef d’Unité', VigimatColors.roleChief, const Color(0xFFF5F3FF)),
      'technician' => ('Technicien', VigimatColors.roleTechnician, const Color(0xFFF0FDFA)),
      'soldier' => ('Soldat · Opérateur', VigimatColors.roleSoldier, const Color(0xFFEFF6FF)),
      _ => (profile.role, VigimatColors.textSecondary, const Color(0xFFF1F5F9)),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: VigimatColors.border, width: 1.1),
        ),
        boxShadow: [
          BoxShadow(
            color: VigimatColors.navy.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ligne supérieure : Logo + Rôle + Boutons actions
            Row(
              children: [
                const VigimatLogo(size: 34),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIGIMAT',
                      style: TextStyle(
                        color: VigimatColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        roleLabel.toUpperCase(),
                        style: TextStyle(
                          color: roleColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (onRefresh != null)
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.sync_rounded),
                    color: VigimatColors.textSecondary,
                    tooltip: 'Synchroniser',
                  ),
                ?trailing,
                if (onProfileTap != null)
                  InkWell(
                    onTap: onProfileTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: VigimatColors.navy.withValues(alpha: 0.07),
                        shape: BoxShape.circle,
                        border: Border.all(color: VigimatColors.border, width: 1.2),
                      ),
                      child: Center(
                        child: Text(
                          (profile.displayName.isNotEmpty
                                  ? profile.displayName[0]
                                  : 'U')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: VigimatColors.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Titre et sous-titre de la section
            Text(
              title,
              style: const TextStyle(
                color: VigimatColors.navy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: VigimatColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
