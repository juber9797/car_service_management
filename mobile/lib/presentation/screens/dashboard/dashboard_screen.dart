import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';
import 'package:car_workshop/presentation/widgets/sync_indicator.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user     = ref.watch(currentUserProvider);
    final jobCards = ref.watch(activeJobCardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Workshop Dashboard'),
            if (user != null)
              Text(
                user.fullName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
                    color: Colors.white70),
              ),
          ],
        ),
        actions: [
          const SyncIndicatorButton(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'logout') ref.read(authProvider.notifier).logout();
              if (v == 'technician') context.go('/technician');
            },
            itemBuilder: (_) => [
              if (user?.role == UserRole.technician)
                const PopupMenuItem(value: 'technician', child: Text('My Tasks')),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),

      // Floating action button for admins/receptionists only
      floatingActionButton: user?.role != UserRole.technician
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New Job Card'),
              backgroundColor: AppColors.primary,
              onPressed: () {/* navigate to create job card */},
            )
          : null,

      body: Column(
        children: [
          // ── Summary strip ──────────────────────────────────────────
          _SummaryStrip(jobCards: jobCards),
          const SizedBox(height: 4),

          // ── Job cards list ─────────────────────────────────────────
          Expanded(
            child: jobCards.when(
              loading: () => _LoadingShimmer(),
              error:   (e, _) => _ErrorState(message: e.toString()),
              data:    (cards) => cards.isEmpty
                  ? const _EmptyState()
                  : _JobCardList(cards: cards),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Summary strip at the top
// ─────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.jobCards});
  final AsyncValue<List<JobCardsTableData>> jobCards;

  @override
  Widget build(BuildContext context) {
    final cards = jobCards.valueOrNull ?? [];
    final byStatus = {
      'pending':     cards.where((c) => c.status == 'pending').length,
      'in_progress': cards.where((c) => c.status == 'in_progress').length,
      'on_hold':     cards.where((c) => c.status == 'on_hold').length,
    };

    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _StatChip(label: 'Active',      value: cards.length,              color: Colors.white),
          const SizedBox(width: 8),
          _StatChip(label: 'In Progress', value: byStatus['in_progress']!,  color: AppColors.statusInProgress),
          const SizedBox(width: 8),
          _StatChip(label: 'Pending',     value: byStatus['pending']!,      color: AppColors.statusNotStarted),
          const SizedBox(width: 8),
          _StatChip(label: 'On Hold',     value: byStatus['on_hold']!,      color: Colors.purple),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Colors.white70),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Main job card list
// ─────────────────────────────────────────────

class _JobCardList extends StatelessWidget {
  const _JobCardList({required this.cards});
  final List<JobCardsTableData> cards;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {/* pull-to-refresh triggers a sync */},
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) => JobCardCard(card: cards[index])
            .animate()
            .fadeIn(delay: Duration(milliseconds: index * 50))
            .slideY(begin: 0.1, end: 0),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// THE VEHICLE CARD — the most critical UI piece
// ─────────────────────────────────────────────

class JobCardCard extends ConsumerWidget {
  const JobCardCard({super.key, required this.card});
  final JobCardsTableData card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksForJobCardProvider(card.id)).valueOrNull ?? [];
    final total     = tasks.length;
    final completed = tasks.where((t) => t.status == 'completed').length;
    final progress  = total == 0 ? 0.0 : completed / total;

    final statusColor = jobCardStatusColor(card.status);
    final statusLabel = jobCardStatusLabel(card.status);
    final isOverdue   = card.promisedAt != null &&
        card.promisedAt!.isBefore(DateTime.now()) &&
        card.status != 'completed';

    return GestureDetector(
      onTap: () => context.push('/job-cards/${card.id}'),
      child: Card(
        child: Column(
          children: [
            // ── Status bar (colored top strip) ──────────────────────
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Header row ─────────────────────────────────────
                  Row(
                    children: [
                      // Job number badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          card.jobNumber,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: AppColors.primary),
                        ),
                      ),
                      const Spacer(),

                      // Status pill
                      _StatusPill(status: card.status),

                      // Overdue indicator
                      if (isOverdue) ...[
                        const SizedBox(width: 6),
                        const _OverdueBadge(),
                      ],
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ── Vehicle info ───────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.directions_car_outlined,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          // License plate is the key identifier for garage staff
                          'Vehicle ${card.vehicleId}', // replaced at runtime with joined data
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── Description preview ────────────────────────────
                  Text(
                    card.description,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 12),

                  // ── Progress bar ───────────────────────────────────
                  _ProgressSection(
                    progress:  progress,
                    total:     total,
                    completed: completed,
                    statusColor: statusColor,
                  ),

                  const SizedBox(height: 10),

                  // ── Footer: promise date + quick action ───────────
                  Row(
                    children: [
                      if (card.promisedAt != null) ...[
                        Icon(
                          Icons.schedule,
                          size: 13,
                          color: isOverdue
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Due ${DateFormat('d MMM').format(card.promisedAt!)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isOverdue
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                              fontWeight: isOverdue
                                  ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ],
                      const Spacer(),
                      _QuickStatusButton(card: card),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Progress section with labeled bar
// ─────────────────────────────────────────────

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.progress,
    required this.total,
    required this.completed,
    required this.statusColor,
  });

  final double progress;
  final int total, completed;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tasks: $completed / $total',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: 5),

        // Segmented progress bar — each segment is one task
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: total == 0
              ? LinearProgressIndicator(
                  value: 0,
                  backgroundColor: AppColors.border,
                  color: statusColor,
                  minHeight: 7,
                )
              : Row(
                  children: List.generate(total, (i) {
                    final isDone = i < completed;
                    return Expanded(
                      child: Container(
                        height: 7,
                        margin: EdgeInsets.only(right: i < total - 1 ? 2 : 0),
                        decoration: BoxDecoration(
                          color: isDone ? statusColor : AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Quick status transition button on the card
// ─────────────────────────────────────────────

class _QuickStatusButton extends ConsumerWidget {
  const _QuickStatusButton({required this.card});
  final JobCardsTableData card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(taskActionsProvider);

    String? nextLabel;
    JobCardStatus? nextStatus;

    switch (card.status) {
      case 'pending':
        nextLabel  = 'Start';
        nextStatus = JobCardStatus.inProgress;
      case 'in_progress':
        nextLabel  = 'Complete';
        nextStatus = JobCardStatus.completed;
      default:
        return const SizedBox.shrink();
    }

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.primary),
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () async {
        await actions.updateJobCardStatus(card: card, newStatus: nextStatus!);
      },
      child: Text(nextLabel, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ─────────────────────────────────────────────
// Reusable status pill chip
// ─────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = jobCardStatusColor(status);
    final label = jobCardStatusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _OverdueBadge extends StatelessWidget {
  const _OverdueBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('OVERDUE',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 0.5)),
    );
  }
}

// ─────────────────────────────────────────────
// Shimmer loading skeleton
// ─────────────────────────────────────────────

class _LoadingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.car_repair, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No active job cards',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Tap + to create a new job card',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('Could not load data',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
