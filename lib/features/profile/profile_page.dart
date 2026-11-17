import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../core/vigimat_brand.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.roleLabel,
    required this.onSignOut,
  });

  final String roleLabel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final user = SupabaseConfig.isConfigured
        ? Supabase.instance.client.auth.currentUser
        : null;
    final displayName = user?.userMetadata?['full_name']?.toString().trim();
    final email = user?.email ?? 'Session locale';
    final name = displayName == null || displayName.isEmpty
        ? email
        : displayName;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [VigimatColors.navy, Color(0xFF1B4266)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const VigimatLogoMark(size: 62, onDark: true),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  roleLabel,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email_rounded),
                  title: const Text('Compte'),
                  subtitle: Text(email),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Accès'),
                  subtitle: Text(roleLabel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8D3540),
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}
