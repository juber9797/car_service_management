import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/core/network/api_client.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/data/local/daos/job_card_dao.dart';
import 'package:car_workshop/data/local/daos/sync_queue_dao.dart';

enum SyncState { idle, syncing, error }

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.jobCardDao,
    required this.syncQueueDao,
  });

  final AppDatabase db;
  final ApiClient api;
  final JobCardDao jobCardDao;
  final SyncQueueDao syncQueueDao;

  final _stateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  static const _uuid = Uuid();

  // ── Start the engine ─────────────────────────────────────────────────────
  void start() {
    // Sync when connectivity is restored
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) _triggerSync();
    });

    // Periodic sync
    _periodicTimer = Timer.periodic(AppConstants.syncInterval, (_) => _triggerSync());

    // Initial sync on start
    _triggerSync();
  }

  void stop() {
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _stateController.close();
  }

  void _triggerSync() {
    if (_isSyncing) return;
    unawaited(_runSync());
  }

  // ── Full sync cycle: push pending → pull updates ─────────────────────────
  Future<void> _runSync() async {
    _isSyncing = true;
    _stateController.add(SyncState.syncing);

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) &&
          connectivity.length == 1) {
        return; // offline, skip silently
      }

      await _push();
      await _pull();

      _stateController.add(SyncState.idle);
    } catch (e) {
      debugPrint('[SyncEngine] error: $e');
      _stateController.add(SyncState.error);
    } finally {
      _isSyncing = false;
    }
  }

  // ── PUSH: send queued local changes to server ─────────────────────────────
  Future<void> _push() async {
    final pending = await syncQueueDao.getPending();
    if (pending.isEmpty) return;

    // Mark as syncing to prevent double-submit across concurrent timer firings
    await syncQueueDao.markSyncing(pending.map((e) => e.changeId).toList());

    final changes = pending.map((e) => {
      'changeId':       e.changeId,
      'entityType':     e.entityType,
      'entityId':       e.entityId,
      'operation':      e.operation,
      'payload':        jsonDecode(e.payload),
      'baseVersion':    e.baseVersion,
      'localTimestamp': e.localTimestamp,
    }).toList();

    final response = await api.pushSync({
      'clientId': 'mobile-app',
      'changes':  changes,
    });

    final results = response['results'] as List<dynamic>;

    for (final result in results) {
      final changeId   = result['changeId'] as String;
      final resolution = result['resolution'] as String;

      switch (resolution) {
        case 'accepted':
          await syncQueueDao.markSynced(changeId);
          // Update local version to match server ack
          if (result['serverVersion'] != null) {
            final change = pending.firstWhere((p) => p.changeId == changeId);
            await _applyServerVersion(
              change.entityType, change.entityId,
              result['serverVersion'] as int,
            );
          }

        case 'merged':
          // Server merged our change with its own — refresh from server
          await syncQueueDao.markSynced(changeId);
          final change = pending.firstWhere((p) => p.changeId == changeId);
          await _refreshEntityFromServer(change.entityType, change.entityId);

        case 'rejected':
          final reason = (result['conflict'] as Map?)?['reason'] as String?
              ?? 'Rejected by server';
          await syncQueueDao.markFailed(changeId, reason);

          // If server has a newer version, update local state
          final serverState = (result['conflict'] as Map?)?['serverState'];
          if (serverState != null && serverState is Map<String, dynamic>) {
            final change = pending.firstWhere((p) => p.changeId == changeId);
            await _applyServerState(change.entityType, serverState);
          }
      }
    }
  }

  // ── PULL: fetch all server changes since last sync ────────────────────────
  Future<void> _pull() async {
    // Store last sync cursor in a simple key-value (reuse sync_queue as meta)
    String? since = await _getLastSyncCursor();

    bool hasMore = true;
    String? cursor = since;

    while (hasMore) {
      final response = await api.pullSync(since: cursor);
      final changes  = response['changes'] as List<dynamic>;
      hasMore        = response['hasMore'] as bool? ?? false;
      final serverTime = response['serverTime'] as String;

      await db.transaction(() async {
        for (final change in changes) {
          await _applyPulledChange(change as Map<String, dynamic>);
        }
      });

      // Advance cursor so next pull is incremental
      cursor = response['nextCursor'] as String? ?? serverTime;
      await _saveLastSyncCursor(serverTime);

      if (!hasMore) break;
    }
  }

  // ── Apply a pulled change to local DB ────────────────────────────────────
  Future<void> _applyPulledChange(Map<String, dynamic> change) async {
    final entityType = change['entityType'] as String;
    final operation  = change['operation']  as String;
    final payload    = change['payload']    as Map<String, dynamic>;

    if (entityType == 'job_cards') {
      if (operation == 'delete') {
        await (db.delete(db.jobCardsTable)
          ..where((t) => t.id.equals(payload['id'] as String))).go();
      } else {
        await jobCardDao.upsertJobCard(_jobCardCompanionFromJson(payload));
      }
    } else if (entityType == 'tasks') {
      if (operation == 'delete') {
        await (db.delete(db.tasksTable)
          ..where((t) => t.id.equals(payload['id'] as String))).go();
      } else {
        await jobCardDao.upsertTask(_taskCompanionFromJson(payload));
      }
    }
  }

  // ── Enqueue a change from the app (called by repositories) ───────────────
  Future<void> enqueueChange({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    required int baseVersion,
  }) async {
    await syncQueueDao.enqueue(SyncQueueTableCompanion(
      changeId:       Value(_uuid.v4()),
      entityType:     Value(entityType),
      entityId:       Value(entityId),
      operation:      Value(operation.name),
      payload:        Value(jsonEncode(payload)),
      baseVersion:    Value(baseVersion),
      localTimestamp: Value(DateTime.now().toIso8601String()),
      syncStatus:     const Value('pending'),
      retryCount:     const Value(0),
      createdAt:      Value(DateTime.now()),
      updatedAt:      Value(DateTime.now()),
    ));

    // Eagerly try to sync rather than waiting for the next timer tick
    _triggerSync();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _applyServerVersion(
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

  Future<void> _refreshEntityFromServer(
      String entityType, String entityId) async {
    try {
      if (entityType == 'job_cards') {
        final data = await api.updateJobCard(entityId, {}); // GET via PATCH isn't ideal
        // In production, add GET /job-cards/:id endpoint
        await jobCardDao.upsertJobCard(_jobCardCompanionFromJson(data));
      }
    } catch (_) {
      // Best-effort refresh
    }
  }

  Future<void> _applyServerState(
      String entityType, Map<String, dynamic> state) async {
    if (entityType == 'job_cards') {
      await jobCardDao.upsertJobCard(_jobCardCompanionFromJson(state));
    } else if (entityType == 'tasks') {
      await jobCardDao.upsertTask(_taskCompanionFromJson(state));
    }
  }

  // Minimal cursor storage using a dedicated sync_queue entry with a special changeId
  static const _cursorKey = '__last_sync_cursor__';

  Future<String?> _getLastSyncCursor() async {
    final row = await (db.select(db.syncQueueTable)
      ..where((t) => t.changeId.equals(_cursorKey)))
        .getSingleOrNull();
    return row?.payload;
  }

  Future<void> _saveLastSyncCursor(String cursor) async {
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

  // ── JSON → Companion mappers ───────────────────────────────────────────────

  JobCardsTableCompanion _jobCardCompanionFromJson(Map<String, dynamic> j) {
    return JobCardsTableCompanion(
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
      promisedAt:    Value(j['promisedAt'] != null
                       ? DateTime.parse(j['promisedAt'] as String) : null),
      startedAt:     Value(j['startedAt']  != null
                       ? DateTime.parse(j['startedAt']  as String) : null),
      completedAt:   Value(j['completedAt']!= null
                       ? DateTime.parse(j['completedAt'] as String) : null),
      createdAt:     Value(DateTime.parse(j['createdAt'] as String)),
      updatedAt:     Value(DateTime.parse(
                       j['updatedAt'] as String? ?? j['createdAt'] as String)),
    );
  }

  TasksTableCompanion _taskCompanionFromJson(Map<String, dynamic> j) {
    return TasksTableCompanion(
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
      startedAt:     Value(j['startedAt']   != null
                       ? DateTime.parse(j['startedAt']   as String) : null),
      completedAt:   Value(j['completedAt'] != null
                       ? DateTime.parse(j['completedAt'] as String) : null),
      createdAt:     Value(DateTime.parse(j['createdAt'] as String)),
      updatedAt:     Value(DateTime.parse(
                       j['updatedAt'] as String? ?? j['createdAt'] as String)),
    );
  }
}
