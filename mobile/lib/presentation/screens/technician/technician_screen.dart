import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';
import 'package:car_workshop/presentation/widgets/task_tile.dart';

class TechnicianScreen extends ConsumerWidget {
  const TechnicianScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTasks = ref.watch(myTasksProvider);
    final user    = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Tasks'),
            if (user != null)
              Text(user.fullName,
                  style: const TextStyle(fontSize: 12, color: Colors.white70,
                      fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: myTasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_outlined, size: 64, color: AppColors.border),
                  SizedBox(height: 16),
                  Text('No assigned tasks',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }

          // Group by status
          final pending    = tasks.where((t) => t.status == 'pending').toList();
          final inProgress = tasks.where((t) => t.status == 'in_progress').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (inProgress.isNotEmpty) ...[
                _SectionHeader(
                    title: 'In Progress (${inProgress.length})',
                    color: AppColors.statusInProgress),
                const SizedBox(height: 8),
                ...inProgress.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TaskTile(task: t),
                    )),
                const SizedBox(height: 16),
              ],
              if (pending.isNotEmpty) ...[
                _SectionHeader(
                    title: 'Pending (${pending.length})',
                    color: AppColors.statusNotStarted),
                const SizedBox(height: 8),
                ...pending.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TaskTile(task: t),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 16,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
