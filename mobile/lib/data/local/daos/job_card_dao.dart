import 'package:drift/drift.dart';
import '../database.dart';
import 'package:car_workshop/core/constants/app_constants.dart';

part 'job_card_dao.g.dart';

@DriftAccessor(tables: [JobCardsTable, TasksTable, VehiclesTable, CustomersTable])
class JobCardDao extends DatabaseAccessor<AppDatabase> with _$JobCardDaoMixin {
  JobCardDao(super.db);

  // ── Watches all active job cards with their task counts ──────────────────
  Stream<List<JobCardsTableData>> watchActive(String garageId) {
    return (select(jobCardsTable)
      ..where((t) => t.garageId.equals(garageId) &
          t.status.isNotIn(['completed', 'cancelled']))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  // ── Watches a single job card ─────────────────────────────────────────────
  Stream<JobCardsTableData?> watchOne(String id) {
    return (select(jobCardsTable)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  // ── Tasks for a job card ──────────────────────────────────────────────────
  Stream<List<TasksTableData>> watchTasksForCard(String jobCardId) {
    return (select(tasksTable)
      ..where((t) => t.jobCardId.equals(jobCardId))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder),
                 (t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  // ── Tasks assigned to a technician ───────────────────────────────────────
  Stream<List<TasksTableData>> watchTechnicianTasks(
      String garageId, String userId) {
    return (select(tasksTable)
      ..where((t) =>
          t.garageId.equals(garageId) &
          t.assignedToId.equals(userId) &
          t.status.isNotIn(['completed', 'cancelled']))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  // ── Upsert a job card (from API pull) ─────────────────────────────────────
  Future<void> upsertJobCard(JobCardsTableCompanion card) {
    return into(jobCardsTable).insertOnConflictUpdate(card);
  }

  // ── Upsert a task ─────────────────────────────────────────────────────────
  Future<void> upsertTask(TasksTableCompanion task) {
    return into(tasksTable).insertOnConflictUpdate(task);
  }

  // ── Optimistically update task status ─────────────────────────────────────
  Future<void> updateTaskStatus({
    required String taskId,
    required TaskStatus status,
    double? actualHours,
  }) {
    return (update(tasksTable)..where((t) => t.id.equals(taskId))).write(
      TasksTableCompanion(
        status:      Value(status.apiValue),
        actualHours: actualHours != null ? Value(actualHours) : const Value.absent(),
        startedAt:   status == TaskStatus.inProgress
                       ? Value(DateTime.now()) : const Value.absent(),
        completedAt: status == TaskStatus.completed
                       ? Value(DateTime.now()) : const Value.absent(),
        updatedAt:   Value(DateTime.now()),
        version:     const Value.absent(), // incremented by sync engine on ack
      ),
    );
  }

  // ── Optimistically update job card status ────────────────────────────────
  Future<void> updateJobCardStatus(String id, JobCardStatus status) {
    return (update(jobCardsTable)..where((t) => t.id.equals(id))).write(
      JobCardsTableCompanion(
        status:      Value(status.apiValue),
        startedAt:   status == JobCardStatus.inProgress
                       ? Value(DateTime.now()) : const Value.absent(),
        completedAt: status == JobCardStatus.completed
                       ? Value(DateTime.now()) : const Value.absent(),
        updatedAt:   Value(DateTime.now()),
      ),
    );
  }

  // ── Task counts per job card for progress calculation ─────────────────────
  Future<({int total, int completed})> taskCounts(String jobCardId) async {
    final all = await (select(tasksTable)
      ..where((t) => t.jobCardId.equals(jobCardId))).get();
    final done = all.where((t) => t.status == 'completed').length;
    return (total: all.length, completed: done);
  }
}
