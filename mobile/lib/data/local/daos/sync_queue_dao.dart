import 'package:drift/drift.dart';
import '../database.dart';
import 'package:car_workshop/core/constants/app_constants.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueueTable])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  // ── Enqueue a local change for later sync ────────────────────────────────
  Future<void> enqueue(SyncQueueTableCompanion entry) {
    return into(syncQueueTable).insertOnConflictUpdate(entry);
  }

  // ── Fetch all pending changes, ordered by creation time ──────────────────
  Future<List<SyncQueueTableData>> getPending() {
    return (select(syncQueueTable)
      ..where((t) =>
          t.syncStatus.equals('pending') |
          // retry failed items with < maxRetries
          (t.syncStatus.equals('failed') &
           t.retryCount.isSmallerThanValue(AppConstants.maxRetryAttempts)))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(AppConstants.syncBatchSize))
        .get();
  }

  // ── Mark a change as syncing (prevents double-submit) ────────────────────
  Future<void> markSyncing(List<String> changeIds) {
    return (update(syncQueueTable)
      ..where((t) => t.changeId.isIn(changeIds)))
        .write(SyncQueueTableCompanion(
          syncStatus: const Value('syncing'),
          updatedAt:  Value(DateTime.now()),
        ));
  }

  // ── Mark accepted by server ───────────────────────────────────────────────
  Future<void> markSynced(String changeId) {
    return (delete(syncQueueTable)
      ..where((t) => t.changeId.equals(changeId)))
        .go();
  }

  // ── Mark rejected or errored — increment retry count ─────────────────────
  Future<void> markFailed(String changeId, String error) async {
    final row = await (select(syncQueueTable)
      ..where((t) => t.changeId.equals(changeId)))
        .getSingleOrNull();
    if (row == null) return;

    await (update(syncQueueTable)
      ..where((t) => t.changeId.equals(changeId)))
        .write(SyncQueueTableCompanion(
          syncStatus:   const Value('failed'),
          retryCount:   Value(row.retryCount + 1),
          errorMessage: Value(error),
          updatedAt:    Value(DateTime.now()),
        ));
  }

  // ── Count of pending/failed items (for badge indicator) ──────────────────
  Stream<int> watchPendingCount() {
    final query = customSelect(
      'SELECT COUNT(*) AS cnt FROM sync_queue WHERE sync_status IN (\'pending\', \'failed\')',
      readsFrom: {syncQueueTable},
    );
    return query.watch().map((rows) => rows.first.read<int>('cnt'));
  }
}
