import 'package:workmanager/workmanager.dart';

const _syncTaskId = 'vigimat-pending-sync';
const _syncTaskName = 'vigimat.sync.pending';

Future<void> scheduleBackgroundSync() => Workmanager().registerOneOffTask(
  _syncTaskId,
  _syncTaskName,
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingWorkPolicy.replace,
  backoffPolicy: BackoffPolicy.exponential,
  backoffPolicyDelay: const Duration(seconds: 30),
);
