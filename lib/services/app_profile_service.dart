import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import 'local_report_store.dart';

class AppProfileService {
  Future<AppUserProfile> loadForCurrentUser() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Session utilisateur absente.');
    final cached = await LocalReportStore.instance.getProfile(user.id);
    final connectivity = await Connectivity().checkConnectivity();
    if (cached != null &&
        connectivity.every((result) => result == ConnectivityResult.none)) {
      return cached;
    }

    try {
      final result = await client.rpc('get_my_app_profile');
      if (result is! Map) {
        throw const FormatException('Profil VIGIMAT introuvable.');
      }
      final profile = AppUserProfile.fromMap(Map<String, Object?>.from(result));
      if (profile.userId != user.id) {
        throw const FormatException(
          'Profil VIGIMAT associé à un autre compte.',
        );
      }
      await LocalReportStore.instance.saveProfile(profile);
      return profile;
    } catch (error) {
      if (cached != null) return cached;
      throw StateError(
        'Connectez-vous en ligne une première fois pour activer ce compte. $error',
      );
    }
  }
}
