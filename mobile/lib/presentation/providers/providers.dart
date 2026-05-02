import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/core/network/api_client.dart';
import 'package:car_workshop/core/storage/secure_storage.dart';
import 'package:car_workshop/core/sync/sync_engine.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/data/local/daos/job_card_dao.dart';
import 'package:car_workshop/data/local/daos/sync_queue_dao.dart';
import 'package:car_workshop/domain/models/models.dart';

// ─────────────────────────────────────────────────────────────
// Infrastructure providers
// ─────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService(const FlutterSecureStorage());
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.read(secureStorageProvider));
});

final jobCardDaoProvider = Provider<JobCardDao>((ref) {
  return JobCardDao(ref.read(databaseProvider));
});

final syncQueueDaoProvider = Provider<SyncQueueDao>((ref) {
  return SyncQueueDao(ref.read(databaseProvider));
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db:           ref.read(databaseProvider),
    api:          ref.read(apiClientProvider),
    jobCardDao:   ref.read(jobCardDaoProvider),
    syncQueueDao: ref.read(syncQueueDaoProvider),
  );
  ref.onDispose(engine.stop);
  return engine;
});

// ─────────────────────────────────────────────────────────────
// Auth providers
// ─────────────────────────────────────────────────────────────

final currentUserProvider = StateProvider<AppUser?>((ref) => null);

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref),
);

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  AuthNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<bool> login({
    required String email,
    required String password,
    required String garageId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final api     = _ref.read(apiClientProvider);
      final storage = _ref.read(secureStorageProvider);

      final result = await api.login(
        email:    email,
        password: password,
        garageId: garageId,
      );

      final tokens = result['tokens'] as Map<String, dynamic>;
      final user   = AppUser.fromJson(
        result['user'] as Map<String, dynamic>,
      );

      await Future.wait([
        storage.saveTokens(
          accessToken:  tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String,
        ),
        storage.saveGarageId(garageId),
        storage.saveUser(user),
      ]);

      _ref.read(currentUserProvider.notifier).state = user;

      // Start sync engine after successful login
      _ref.read(syncEngineProvider).start();

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> logout() async {
    _ref.read(syncEngineProvider).stop();
    await _ref.read(secureStorageProvider).clearAll();
    _ref.read(currentUserProvider.notifier).state = null;
    state = const AsyncValue.data(null);
  }

  Future<bool> tryRestoreSession() async {
    final storage = _ref.read(secureStorageProvider);
    final user    = await storage.getUser();
    if (user == null) return false;
    _ref.read(currentUserProvider.notifier).state = user;
    _ref.read(syncEngineProvider).start();
    return true;
  }
}

// ─────────────────────────────────────────────────────────────
// Job Card providers — stream from local DB (reactive, offline-first)
// ─────────────────────────────────────────────────────────────

final activeJobCardsProvider = StreamProvider<List<JobCardsTableData>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return ref.read(jobCardDaoProvider).watchActive(user.garageId);
});

final jobCardProvider = StreamProvider.family<JobCardsTableData?, String>(
  (ref, id) => ref.read(jobCardDaoProvider).watchOne(id),
);

final tasksForJobCardProvider =
    StreamProvider.family<List<TasksTableData>, String>(
  (ref, jobCardId) =>
      ref.read(jobCardDaoProvider).watchTasksForCard(jobCardId),
);

// ─────────────────────────────────────────────────────────────
// Technician view — only tasks assigned to current user
// ─────────────────────────────────────────────────────────────

final myTasksProvider = StreamProvider<List<TasksTableData>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return ref
      .read(jobCardDaoProvider)
      .watchTechnicianTasks(user.garageId, user.id);
});

// ─────────────────────────────────────────────────────────────
// Sync state providers
// ─────────────────────────────────────────────────────────────

final syncStateProvider = StreamProvider<SyncState>((ref) {
  return ref.read(syncEngineProvider).stateStream;
});

final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.read(syncQueueDaoProvider).watchPendingCount();
});

// ─────────────────────────────────────────────────────────────
// Task actions — write through local DB then enqueue sync
// ─────────────────────────────────────────────────────────────

final taskActionsProvider = Provider<TaskActions>((ref) => TaskActions(ref));

class TaskActions {
  const TaskActions(this._ref);
  final Ref _ref;

  Future<void> updateStatus({
    required TasksTableData task,
    required TaskStatus newStatus,
    double? actualHours,
  }) async {
    final dao    = _ref.read(jobCardDaoProvider);
    final engine = _ref.read(syncEngineProvider);

    // 1. Optimistic local update — UI refreshes instantly
    await dao.updateTaskStatus(
      taskId:      task.id,
      status:      newStatus,
      actualHours: actualHours,
    );

    // 2. Enqueue for server sync
    await engine.enqueueChange(
      entityType: 'tasks',
      entityId:   task.id,
      operation:  SyncOperation.update,
      payload: {
        'status':      newStatus.apiValue,
        if (actualHours != null) 'actualHours': actualHours,
        'version':     task.version,
      },
      baseVersion: task.version,
    );
  }

  Future<void> updateJobCardStatus({
    required JobCardsTableData card,
    required JobCardStatus newStatus,
  }) async {
    final dao    = _ref.read(jobCardDaoProvider);
    final engine = _ref.read(syncEngineProvider);

    await dao.updateJobCardStatus(card.id, newStatus);

    await engine.enqueueChange(
      entityType: 'job_cards',
      entityId:   card.id,
      operation:  SyncOperation.update,
      payload: {
        'status':  newStatus.apiValue,
        'version': card.version,
      },
      baseVersion: card.version,
    );
  }
}
