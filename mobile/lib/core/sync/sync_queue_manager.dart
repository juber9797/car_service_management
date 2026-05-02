import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/core/network/api_client.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/data/local/daos/job_card_dao.dart';
import 'package:car_workshop/data/local/daos/sync_queue_dao.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SyncQueueManager
//
// Responsibilities:
//   1. Accept local writes and persist them to sync_queue immediately
//      (write-ahead log pattern — the app never talks to the network directly)
//   2. Drain the queue when network is available:
//      - batch up to SYNC_BATCH_SIZE pending items
//      - POST /sync/push
//      - per-result: mark synced / merge local state / mark failed
//   3. Exponential backoff per failed item (not per batch)
//   4. Pull remote changes and apply tombstones
//   5. Emit a stream of SyncStatus for the UI to display
// ─────────────────────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, error, offline }

class SyncQueueManager {
  SyncQueueManager({
    required this.db,
    required this.api,
    required this.jobCardDao,
    required this.syncQueueDao,
    required this.clientId,
  });

  final AppDatabase   db;
  final ApiClient     api;
  final JobCardDao    jobCardDao;
  final SyncQueueDao  syncQueueDao;
  final String        clientId;

  static const _uuid          = Uuid();
  static const _maxRetries    = AppConstants.maxRetryAttempts;   // 3
  static const _batchSize     = AppConstants.syncBatchSize;       // 50
  static const _baseDelay     = Duration(seconds: 2);
  static const _maxDelay      = Duration(minutes: 5);

  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;

  Timer?                                 _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool                                   _isSyncing    = false;
  bool                                   _isOnline     = true;
  int                                    _failStreak   = 0;      // consecutive failed cycles

  // ── Lifecycle ────────────────────────────────────────────────────────────

  void start() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    _periodicTimer = Timer.periodic(
      AppConstants.syncInterval, (_) => _maybeDrainQueue());

    // First drain on start
    _maybeDrainQueue();
  }

  void stop() {
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _statusCtrl.close();
  }

  // ── Public: enqueue a local change ───────────────────────────────────────

  /// Called immediately after every local DB write.
  /// Never throws — the write is durable in SQLite before this returns.
  Future<String> enqueue({
    required String                  entityType,
    required String                  entityId,
    required SyncOperation           operation,
    required Map<String, dynamic>    payload,
    required int                     baseVersion,
  }) async {
    final changeId = _uuid.v4();
    final now      = DateTime.now();

    await syncQueueDao.enqueue(SyncQueueTableCompanion(
      changeId:       Value(changeId),
      entityType:     Value(entityType),
      entityId:       Value(entityId),
      operation:      Value(operation.name),
      payload:        Value(jsonEncode(payload)),
      baseVersion:    Value(baseVersion),
      localTimestamp: Value(now.toIso8601String()),
      syncStatus:     const Value('pending'),
      retryCount:     const Value(0),
      createdAt:      Value(now),
      updatedAt:      Value(now),
    ));

    // Eagerly drain — don't wait for the next timer tick
    _maybeDrainQueue();
    return changeId;
  }

  // ── Network state ────────────────────────────────────────────────────────

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    if (!wasOnline && _isOnline) {
      debugPrint('[SyncQueue] Network restored — draining queue');
      _failStreak = 0;
      _maybeDrainQueue();
    } else if (!_isOnline) {
      _statusCtrl.add(SyncStatus.offline);
    }
  }

  // ── Drain gate ────────────────────────────────────────────────────────────

  void _maybeDrainQueue() {
    if (_isSyncing || !_isOnline) return;
    unawaited(_drainCycle());
  }

  // ── Full sync cycle ───────────────────────────────────────────────────────

  Future<void> _drainCycle() async {
    _isSyncing = true;
    _statusCtrl.add(SyncStatus.syncing);

    try {
      await _push();
      await _pull();
      _failStreak = 0;
      _statusCtrl.add(SyncStatus.idle);
    } catch (e) {
      _failStreak++;
      debugPrint('[SyncQueue] cycle failed (streak=$_failStreak): $e');
      _statusCtrl.add(SyncStatus.error);
      _scheduleRetryAfterBackoff();
    } finally {
      _isSyncing = false;
    }
  }

  // ── Exponential backoff for full cycle failures ───────────────────────────
  //
  // After a network error (not a per-item conflict) we back off the
  // entire cycle using truncated binary exponential backoff:
  //
  //   attempt 1 → wait  2s
  //   attempt 2 → wait  4s
  //   attempt 3 → wait  8s
  //   attempt 4 → wait 16s
  //   ...capped at 5 minutes
  //
  // Individual item retry is handled by retryCount on the queue row.

  void _scheduleRetryAfterBackoff() {
    final rawDelay = _baseDelay * pow(2, _failStreak - 1).toInt();
    final jitter   = Duration(milliseconds: Random().nextInt(1000));
    final delay    = rawDelay > _maxDelay
        ? _maxDelay + jitter
        : rawDelay + jitter;

    debugPrint('[SyncQueue] retrying in ${delay.inSeconds}s');
    Timer(delay, _maybeDrainQueue);
  }

  // ── PUSH ─────────────────────────────────────────────────────────────────

  Future<void> _push() async {
    // Fetch eligible rows: pending OR failed-but-retryable
    final rows = await syncQueueDao.getPending();
    if (rows.isEmpty) return;

    await syncQueueDao.markSyncing(rows.map((r) => r.changeId).toList());

    final batch = rows.map((r) => {
      'changeId':       r.changeId,
      'entityType':     r.entityType,
      'entityId':       r.entityId,
      'operation':      r.operation,
      'payload':        jsonDecode(r.payload) as Map<String, dynamic>,
      'baseVersion':    r.baseVersion,
      'localTimestamp': r.localTimestamp,
    }).toList();

    final response = await api.pushSync({
      'clientId': clientId,
      'changes':  batch,
    });

    final results = (response['results'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    for (final result in results) {
      await _applyPushResult(result, rows);
    }
  }

  Future<void> _applyPushResult(
    Map<String, dynamic>      result,
    List<SyncQueueTableData>  sentRows,
  ) async {
    final changeId   = result['changeId']   as String;
    final resolution = result['resolution'] as String;

    switch (resolution) {

      // ── accepted ──────────────────────────────────────────────────────────
      // Server committed our change as-is. Update local version to match.
      case 'accepted':
        await syncQueueDao.markSynced(changeId);

        final serverVersion = result['serverVersion'] as int?;
        if (serverVersion != null) {
          final row = sentRows.firstWhere((r) => r.changeId == changeId);
          await _applyVersionAck(row.entityType, row.entityId, serverVersion);
        }

      // ── merged ────────────────────────────────────────────────────────────
      // Server merged our change with a concurrent update.
      // Apply the server's merged state locally so both devices converge.
      case 'merged':
        await syncQueueDao.markSynced(changeId);

        final serverState = result['serverState'] as Map<String, dynamic>?;
        if (serverState != null) {
          final row = sentRows.firstWhere((r) => r.changeId == changeId);
          await _applyServerState(row.entityType, serverState);
        }

      // ── rejected ──────────────────────────────────────────────────────────
      // Server could not accept our change (e.g. delete blocked by workflow).
      // Apply server state locally and stop retrying this change.
      case 'rejected':
        final reason     = (result['conflict'] as Map?)?['reason'] as String?
            ?? 'Rejected by server';
        final serverState = result['serverState'] as Map<String, dynamic>?;

        await syncQueueDao.markFailed(changeId, reason);

        if (serverState != null) {
          final row = sentRows.firstWhere((r) => r.changeId == changeId);
          await _applyServerState(row.entityType, serverState);
        }
    }
  }

  // ── PULL ─────────────────────────────────────────────────────────────────

  Future<void> _pull() async {
    String? cursor = await _readCursor();

    // Paginate until server says hasMore=false
    while (true) {
      final response = await api.pullSync(since: cursor);

      final changes    = (response['changes']    as List).cast<Map<String, dynamic>>();
      final tombstones = (response['tombstones'] as List).cast<Map<String, dynamic>>();
      final hasMore    = response['hasMore']    as bool? ?? false;
      final serverTime = response['serverTime'] as String;

      await db.transaction(() async {
        for (final change in changes) {
          await _applyPulledChange(change);
        }
        for (final tombstone in tombstones) {
          await _applyTombstone(tombstone);
        }
      });

      cursor = response['nextCursor'] as String? ?? serverTime;
      await _saveCursor(serverTime);

      if (!hasMore) break;
    }
  }

  Future<void> _applyPulledChange(Map<String, dynamic> change) async {
    final entityType = change['entityType'] as String;
    final operation  = change['operation']  as String;
    final payload    = change['payload']    as Map<String, dynamic>;

    if (entityType == 'job_cards') {
      if (operation == 'delete') {
        await (db.delete(db.jobCardsTable)
          ..where((t) => t.id.equals(payload['id'] as String))).go();
      } else {
        await jobCardDao.upsertJobCard(_jobCardCompanion(payload));
      }
    } else if (entityType == 'tasks') {
      if (operation == 'delete') {
        await (db.delete(db.tasksTable)
          ..where((t) => t.id.equals(payload['id'] as String))).go();
      } else {
        await jobCardDao.upsertTask(_taskCompanion(payload));
      }
    }
  }

  /// Tombstone: server deleted an entity — purge from local DB
  Future<void> _applyTombstone(Map<String, dynamic> t) async {
    final entityType = t['entityType'] as String;
    final entityId   = t['entityId']   as String;

    if (entityType == 'job_cards') {
      await (db.delete(db.jobCardsTable)
        ..where((r) => r.id.equals(entityId))).go();
    } else if (entityType == 'tasks') {
      await (db.delete(db.tasksTable)
        ..where((r) => r.id.equals(entityId))).go();
    }

    // Also remove any pending sync-queue entries for this entity
    // — there's no point syncing changes for a deleted record
    await (db.delete(db.syncQueueTable)
      ..where((r) =>
          r.entityId.equals(entityId) &
          r.entityType.equals(entityType))).go();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _applyVersionAck(
      String entityType, String entityId, int version) async {
    if (entityType == 'job_cards') {
      await (db.update(db.jobCardsTable)
        ..where((t) => t.id.equals(entityId)))
          .write(JobCardsTableCompanion(version: Value(version)));
    } else if (entityType == 'tasks') {
      await (db.update(db.tasksTable)
        ..where((t) => t.id.equals(entityId)))
          .write(TasksTableCompanion(version: Value(version)));
    }
  }

  Future<void> _applyServerState(
      String entityType, Map<String, dynamic> state) async {
    if (entityType == 'job_cards') {
      await jobCardDao.upsertJobCard(_jobCardCompanion(state));
    } else if (entityType == 'tasks') {
      await jobCardDao.upsertTask(_taskCompanion(state));
    }
  }

  // Cursor stored as a special sync_queue meta row
  static const _cursorKey = '__last_sync_cursor__';

  Future<String?> _readCursor() async {
    final row = await (db.select(db.syncQueueTable)
      ..where((t) => t.changeId.equals(_cursorKey))).getSingleOrNull();
    return row?.payload;
  }

  Future<void> _saveCursor(String cursor) async {
    await db.into(db.syncQueueTable).insertOnConflictUpdate(
      SyncQueueTableCompanion(
        changeId:       const Value(_cursorKey),
        entityType:     const Value('__meta__'),
        entityId:       const Value('__meta__'),
        operation:      const Value('__meta__'),
        payload:        Value(cursor),
        baseVersion:    const Value(0),
        localTimestamp: Value(cursor),
        syncStatus:     const Value('synced'),
        retryCount:     const Value(0),
        createdAt:      Value(DateTime.now()),
        updatedAt:      Value(DateTime.now()),
      ),
    );
  }

  JobCardsTableCompanion _jobCardCompanion(Map<String, dynamic> j) =>
      JobCardsTableCompanion(
        id:            Value(j['id'] as String),
        garageId:      Value(j['garageId'] as String),
        jobNumber:     Value(j['jobNumber'] as String),
        vehicleId:     Value(j['vehicleId'] as String),
        customerId:    Value(j['customerId'] as String),
        assignedToId:  Value(j['assignedToId'] as String?),
        status:        Value(j['status'] as String),
        description:   Value(j['description'] as String),
        estimatedHours: Value((j['estimatedHours'] as num?)?.toDouble()),
        actualHours:   Value((j['actualHours'] as num?)?.toDouble()),
        mileageIn:     Value(j['mileageIn'] as int?),
        notes:         Value(j['notes'] as String?),
        version:       Value(j['version'] as int? ?? 1),
        promisedAt:    Value(j['promisedAt'] != null ? DateTime.parse(j['promisedAt'] as String) : null),
        startedAt:     Value(j['startedAt']  != null ? DateTime.parse(j['startedAt']  as String) : null),
        completedAt:   Value(j['completedAt']!= null ? DateTime.parse(j['completedAt'] as String) : null),
        createdAt:     Value(DateTime.parse(j['createdAt'] as String)),
        updatedAt:     Value(DateTime.parse(j['updatedAt'] as String? ?? j['createdAt'] as String)),
      );

  TasksTableCompanion _taskCompanion(Map<String, dynamic> j) =>
      TasksTableCompanion(
        id:            Value(j['id'] as String),
        garageId:      Value(j['garageId'] as String),
        jobCardId:     Value(j['jobCardId'] as String),
        assignedToId:  Value(j['assignedToId'] as String?),
        title:         Value(j['title'] as String),
        description:   Value(j['description'] as String?),
        status:        Value(j['status'] as String),
        estimatedHours: Value((j['estimatedHours'] as num?)?.toDouble()),
        actualHours:   Value((j['actualHours'] as num?)?.toDouble()),
        laborRate:     Value((j['laborRate'] as num?)?.toDouble()),
        sortOrder:     Value(j['sortOrder'] as int? ?? 0),
        version:       Value(j['version'] as int? ?? 1),
        startedAt:     Value(j['startedAt']   != null ? DateTime.parse(j['startedAt']   as String) : null),
        completedAt:   Value(j['completedAt'] != null ? DateTime.parse(j['completedAt'] as String) : null),
        createdAt:     Value(DateTime.parse(j['createdAt'] as String)),
        updatedAt:     Value(DateTime.parse(j['updatedAt'] as String? ?? j['createdAt'] as String)),
      );
}
