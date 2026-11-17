import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/mali_identity.dart';
import '../../core/vigimat_brand.dart';
import '../../services/push_notification_service.dart';
import '../chief/chief_dashboard_page.dart';
import '../home/reports_home_page.dart';

Map<String, dynamic>? _decodeJwtPayload(String? token) {
  if (token == null || token.split('.').length != 3) return null;

  try {
    final payload = token.split('.')[1];
    final normalized = payload + '=' * ((4 - payload.length % 4) % 4);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final parsed = jsonDecode(decoded);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      return Map<String, dynamic>.from(parsed);
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? resolveUserRole(User user, {String? accessToken}) {
  final metadataRole = user.appMetadata['role'] ?? user.userMetadata?['role'];
  final normalizedMetadataRole = metadataRole?.toString().trim().toLowerCase();
  if (normalizedMetadataRole != null && normalizedMetadataRole.isNotEmpty) {
    return normalizedMetadataRole;
  }

  final jwtPayload = _decodeJwtPayload(accessToken);
  final jwtRole =
      jwtPayload?['app_metadata']?['role'] ??
      jwtPayload?['user_metadata']?['role'] ??
      jwtPayload?['role'];
  return jwtRole?.toString().trim().toLowerCase();
}

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

  @override
  void initState() {
    super.initState();
    _user = _client.auth.currentUser;
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (state) {
        if (mounted) {
          setState(() {
            _user = state.session?.user;
            _authError = null;
          });
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

    final role = resolveUserRole(
      user,
      accessToken: _client.auth.currentSession?.accessToken,
    );
    switch (role) {
      case 'technician':
        return ReportsHomePage(onSignOut: () => unawaited(_signOut()));
      case 'unit_head':
        return ChiefDashboardPage(onSignOut: () => unawaited(_signOut()));
      default:
        return _messagePage(
          'Accès non attribué',
          'Votre compte est connecté, mais aucun rôle autorisé ne lui est attribué. Contactez l’administrateur de l’application.',
          onSignOut: () => unawaited(_signOut()),
        );
    }
  }

  Future<void> _signOut() async {
    try {
      await PushNotificationService.instance.unregisterCurrentDevice();
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
              const VigimatLogoMark(size: 60),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onSignOut != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onSignOut,
                  child: const Text('Se déconnecter'),
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
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    final heroHeight = ((MediaQuery.sizeOf(context).width - 40) * 0.52).clamp(
      170.0,
      245.0,
    );
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF06172B), Color(0xFF102B49), Color(0xFF071B31)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, child) => Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - progress)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const MaliIdentity(),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/vigimat_login_hero.png',
                          width: double.infinity,
                          height: heroHeight,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xF5123453), Color(0xF5071B31)],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: VigimatColors.turquoise.withValues(
                              alpha: 0.75,
                            ),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: VigimatColors.turquoise.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 26,
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
                              Text(
                                'Accédez à votre espace',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Connectez-vous avec votre compte autorisé.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFFB8CDE2)),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                style: const TextStyle(color: Colors.white),
                                decoration: _loginFieldDecoration(
                                  'Adresse e-mail',
                                  Icons.person_outline_rounded,
                                ),
                                validator: (value) =>
                                    value == null || !value.contains('@')
                                    ? 'Entrez une adresse e-mail valide.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                style: const TextStyle(color: Colors.white),
                                decoration: _loginFieldDecoration(
                                  'Mot de passe',
                                  Icons.lock_outline_rounded,
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.white,
                                    ),
                                    tooltip: _obscurePassword
                                        ? 'Afficher le mot de passe'
                                        : 'Masquer le mot de passe',
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'Entrez votre mot de passe.'
                                    : null,
                                onFieldSubmitted: (_) => _signIn(),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: _error == null
                                    ? const SizedBox.shrink()
                                    : Container(
                                        key: ValueKey(_error),
                                        margin: const EdgeInsets.only(top: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF1F0),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.error_outline,
                                              color: VigimatColors.red,
                                              size: 19,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: const TextStyle(
                                                  color: VigimatColors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _loading ? null : _signIn,
                                style: FilledButton.styleFrom(
                                  backgroundColor: VigimatColors.turquoise,
                                  foregroundColor: VigimatColors.navy,
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _loading
                                      ? const SizedBox(
                                          key: ValueKey('loading'),
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: VigimatColors.navy,
                                          ),
                                        )
                                      : const FittedBox(
                                          key: ValueKey('submit'),
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.login_rounded),
                                              SizedBox(width: 9),
                                              Text('Se connecter'),
                                              SizedBox(width: 7),
                                              Icon(Icons.arrow_forward_rounded),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Les comptes et leurs rôles sont gérés par l’administrateur.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFFB8CDE2)),
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

  InputDecoration _loginFieldDecoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(
        color: VigimatColors.turquoise.withValues(alpha: 0.58),
      ),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFB8CDE2)),
      prefixIcon: Icon(icon, color: VigimatColors.turquoise),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(
          color: VigimatColors.turquoise,
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: VigimatColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: VigimatColors.red, width: 1.6),
      ),
    );
  }
}
