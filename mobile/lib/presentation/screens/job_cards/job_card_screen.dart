import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';
import 'package:car_workshop/presentation/widgets/task_tile.dart';

class JobCardScreen extends ConsumerWidget {
  const JobCardScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobCardAsync = ref.watch(jobCardProvider(id));
    final tasksAsync   = ref.watch(tasksForJobCardProvider(id));
    final user         = ref.watch(currentUserProvider);
    final isAdmin      = user?.role != null && user!.role.name != 'technician';

    return Scaffold(
      appBar: AppBar(
        title: jobCardAsync.when(
          data: (c) => Text(c?.jobNumber ?? ''),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Generate Invoice',
              onPressed: () => context.push('/job-cards/$id/billing'),
            ),
          IconButton(
            icon: const Icon(Icons.add_task),
            tooltip: 'Add Task',
            onPressed: () => context.push('/job-cards/$id/add-task'),
          ),
        ],
      ),

      body: jobCardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('Job card not found'));
          }
          return _JobCardBody(card: card, tasksAsync: tasksAsync);
        },
      ),
    );
  }
}

class _JobCardBody extends ConsumerWidget {
  const _JobCardBody({required this.card, required this.tasksAsync});
  final JobCardsTableData card;
  final AsyncValue<List<TasksTableData>> tasksAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [

        // ── Info card ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Status: ',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        _StatusPill(status: card.status),
                        const Spacer(),
                        _QuickStatusDropdown(card: card),
                      ],
                    ),
                    const Divider(height: 20),

                    _InfoRow(icon: Icons.description_outlined,
                        label: 'Description', value: card.description),

                    if (card.promisedAt != null)
                      _InfoRow(
                        icon: Icons.schedule,
                        label: 'Promised by',
                        value: DateFormat('d MMM yyyy, HH:mm').format(card.promisedAt!),
                        valueColor: card.promisedAt!.isBefore(DateTime.now())
                            ? AppColors.warning : null,
                      ),

                    if (card.estimatedHours != null)
                      _InfoRow(
                          icon: Icons.timer_outlined,
                          label: 'Est. hours',
                          value: '${card.estimatedHours}h'),

                    if (card.mileageIn != null)
                      _InfoRow(
                          icon: Icons.speed_outlined,
                          label: 'Mileage in',
                          value: '${card.mileageIn} km'),

                    if (card.notes != null && card.notes!.isNotEmpty)
                      _InfoRow(
                          icon: Icons.notes_outlined,
                          label: 'Notes',
                          value: card.notes!),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Tasks header ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Text('Tasks',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                tasksAsync.when(
                  data: (tasks) => Text(
                    '(${tasks.where((t) => t.status == 'completed').length}/${tasks.length})',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),

        // ── Task list ─────────────────────────────────────────────
        tasksAsync.when(
          loading: () => const SliverToBoxAdapter(
              child: Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator()))),
          error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error loading tasks: $e'))),
          data: (tasks) => tasks.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('No tasks yet. Tap + to add one.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TaskTile(task: tasks[i]),
                    ),
                    childCount: tasks.length,
                  ),
                ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon, required this.label, required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = jobCardStatusColor(status);
    final label = jobCardStatusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuickStatusDropdown extends ConsumerWidget {
  const _QuickStatusDropdown({required this.card});
  final JobCardsTableData card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = {
      'in_progress': 'Mark In Progress',
      'on_hold':     'Put On Hold',
      'completed':   'Mark Completed',
    };

    return PopupMenuButton<String>(
      icon: const Icon(Icons.edit_outlined, size: 18),
      onSelected: (status) {
        // Map string back to enum
        final s = {
          'in_progress': JobCardStatus.inProgress,
          'on_hold':     JobCardStatus.onHold,
          'completed':   JobCardStatus.completed,
        }[status]!;
        ref.read(taskActionsProvider).updateJobCardStatus(card: card, newStatus: s);
      },
      itemBuilder: (_) => options.entries
          .where((e) => e.key != card.status)
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
    );
  }
}
