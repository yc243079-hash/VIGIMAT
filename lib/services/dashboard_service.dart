import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/dashboard_snapshot.dart';

class DashboardService {
  const DashboardService();

  Future<DashboardSnapshot> load() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase n’est pas configuré.');
    }

    final result = await Supabase.instance.client.rpc(
      'get_maintenance_dashboard_metrics',
    );
    return DashboardSnapshot.fromJson(result);
  }
}
