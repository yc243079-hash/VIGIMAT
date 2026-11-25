import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/mali_identity.dart';
import '../../core/theme/vigimat_colors.dart';
import '../../core/theme/vigimat_logo.dart';
import '../../models/app_user_profile.dart';
import '../../services/app_profile_service.dart';
import '../../widgets/vigimat_button.dart';
import '../../widgets/vigimat_text_field.dart';
import '../chief/chief_dashboard_page.dart';
import '../home/reports_home_page.dart';
import '../soldier/soldier_home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  String? _authError;
  AppUserProfile? _profile;
  bool _profileLoading = false;

  @override
  void initState() {
    super.initState();
    _user = _client.auth.currentUser;
    if (_user != null) {
      _profileLoading = true;
      unawaited(_loadProfile(_user));
    }
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (state) {
        if (mounted) {
          final user = state.session?.user;
          setState(() {
            _user = user;
            _profile = null;
            _profileLoading = user != null;
            _authError = null;
          });
          unawaited(_loadProfile(user));
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _authError = error.toString());
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authError != null) {
      return _messagePage('Session indisponible', _authError!);
    }
    final user = _user;
    if (user == null) {
      return const LoginPage();
    }

    if (_profileLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VigimatLogo(size: 64),
              SizedBox(height: 20),
              CircularProgressIndicator(color: VigimatColors.emerald),
            ],
          ),
        ),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return _messagePage(
        'Profil indisponible',
        _authError ?? 'Le compte ne possède pas de profil VIGIMAT valide.',
        onSignOut: () => unawaited(_signOut()),
      );
    }
    switch (profile.role) {
      case 'technician':
        return ReportsHomePage(
          profile: profile,
          onSignOut: () => unawaited(_signOut()),
        );
      case 'unit_head':
        return ChiefDashboardPage(
          profile: profile,
          onSignOut: () => unawaited(_signOut()),
        );
      case 'soldier':
        return SoldierHomePage(
          profile: profile,
          onSignOut: () => unawaited(_signOut()),
        );
      default:
        return _messagePage(
          'Accès non attribué',
          'Votre compte est connecté, mais aucun rôle autorisé ne lui est attribué. Contactez l’administrateur de l’application.',
          onSignOut: () => unawaited(_signOut()),
        );
    }
  }

  Future<void> _loadProfile(User? user) async {
    if (user == null) {
      if (mounted) setState(() => _profileLoading = false);
      return;
    }
    try {
      final profile = await AppProfileService().loadForCurrentUser();
      if (!mounted || _client.auth.currentUser?.id != user.id) return;
      setState(() {
        _profile = profile;
        _profileLoading = false;
        _authError = null;
      });
    } catch (error) {
      if (!mounted || _client.auth.currentUser?.id != user.id) return;
      setState(() {
        _profile = null;
        _profileLoading = false;
        _authError = error.toString();
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Déconnexion impossible : $error')),
      );
    }
  }

  Widget _messagePage(String title, String message, {VoidCallback? onSignOut}) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VigimatLogo(size: 64),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VigimatColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              if (onSignOut != null) ...[
                const SizedBox(height: 20),
                VigimatButton(
                  text: 'Se déconnecter',
                  onPressed: onSignOut,
                  variant: VigimatButtonVariant.secondary,
                  fullWidth: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillAccount(String email) {
    setState(() {
      _emailController.text = email;
      _passwordController.text = 'MotDePasse123!';
      _error = null;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Connexion refusée : $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = ((MediaQuery.sizeOf(context).width - 40) * 0.50).clamp(
      165.0,
      240.0,
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: VigimatColors.heroGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, child) => Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - progress)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // En-tête : Devise Nationale & Logo VIGIMAT
                      const MaliIdentity(),
                      const SizedBox(height: 14),

                      // Image Hero avec badge tactique
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: VigimatColors.turquoise.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(21),
                              child: Image.asset(
                                'assets/images/vigimat_login_hero.png',
                                width: double.infinity,
                                height: heroHeight,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xDD071526),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: VigimatColors.emerald.withValues(alpha: 0.45),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_rounded,
                                    size: 13,
                                    color: VigimatColors.emerald,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'FAMa · Système Embarqué de Soutien',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Carte de Connexion Vitrée Tactique
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xF5132F50), Color(0xF50A1B2F)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: VigimatColors.turquoise.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Marque & Titre
                              const Row(
                                children: [
                                  VigimatLogo(size: 38, onDark: true),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'ESPACE OPÉRATIONNEL',
                                          style: TextStyle(
                                            color: VigimatColors.turquoise,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Connexion Sécurisée',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Sélecteur d'accès rapide pour tests
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _RoleQuickChip(
                                    label: 'Soldat',
                                    icon: Icons.person_rounded,
                                    color: VigimatColors.roleSoldier,
                                    onTap: () => _fillAccount('soldat@test.com'),
                                  ),
                                  _RoleQuickChip(
                                    label: 'Chef d’Unité',
                                    icon: Icons.security_rounded,
                                    color: VigimatColors.roleChief,
                                    onTap: () => _fillAccount('chef@test.com'),
                                  ),
                                  _RoleQuickChip(
                                    label: 'Technicien',
                                    icon: Icons.build_rounded,
                                    color: VigimatColors.roleTechnician,
                                    onTap: () => _fillAccount('technicien@test.com'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // Champs Saisie
                              VigimatTextField(
                                controller: _emailController,
                                label: 'Identifiant / E-mail',
                                hint: 'exemple@test.com',
                                icon: Icons.alternate_email_rounded,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                onDark: true,
                                validator: (value) =>
                                    value == null || !value.contains('@')
                                    ? 'Entrez une adresse e-mail valide.'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              VigimatTextField(
                                controller: _passwordController,
                                label: 'Mot de passe',
                                hint: '••••••••••••',
                                icon: Icons.lock_outline_rounded,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                onDark: true,
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'Entrez votre mot de passe.'
                                    : null,
                              ),

                              // Message Erreur
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: _error == null
                                    ? const SizedBox.shrink()
                                    : Container(
                                        key: ValueKey(_error),
                                        margin: const EdgeInsets.only(top: 14),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: VigimatColors.crimsonSoft,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: VigimatColors.crimson.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.error_outline_rounded,
                                              color: VigimatColors.crimson,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: const TextStyle(
                                                  color: VigimatColors.crimsonDark,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 22),

                              // Bouton Connexion
                              VigimatButton(
                                text: 'Se connecter',
                                icon: Icons.login_rounded,
                                trailingIcon: Icons.arrow_forward_rounded,
                                loading: _loading,
                                onPressed: _signIn,
                                height: 52,
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Gestion des comptes et habilitations régie par l’État-Major.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleQuickChip extends StatelessWidget {
  const _RoleQuickChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
