import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../core/supabase_config.dart';
import 'report_sync_service.dart';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != 'vigimat.sync.pending' || !SupabaseConfig.isConfigured) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      return await ReportSyncService(
        onChanged: () {},
        onError: (_) {},
      ).syncPendingInBackground();
    } catch (_) {
      return false;
    }
  });
}
