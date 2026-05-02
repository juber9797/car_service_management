import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task});
  final TasksTableData task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone     = task.status == 'completed';
    final statusColor = taskStatusColor(task.status);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showStatusSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Status indicator circle
              GestureDetector(
                onTap: () => _quickToggle(ref),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? statusColor : Colors.transparent,
                    border: Border.all(
                        color: isDone ? statusColor : AppColors.border,
                        width: 2),
                  ),
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),

              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                      ),
                    ),
                    if (task.description != null && task.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(task.description!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Status chip
                        _MiniChip(
                          label: _statusLabel(task.status),
                          color: statusColor,
                        ),
                        if (task.estimatedHours != null) ...[
                          const SizedBox(width: 6),
                          _MiniChip(
                            label: '${task.estimatedHours}h est.',
                            color: AppColors.textSecondary,
                          ),
                        ],
                        if (task.assignedToId != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.person_outline,
                              size: 12, color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Chevron
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  // One-tap toggle: pending → in_progress → completed
  Future<void> _quickToggle(WidgetRef ref) async {
    final next = switch (task.status) {
      'pending'     => TaskStatus.inProgress,
      'in_progress' => TaskStatus.completed,
      _             => null,
    };
    if (next == null) return;
    await ref.read(taskActionsProvider).updateStatus(
      task:      task,
      newStatus: next,
    );
  }

  // Full status bottom sheet
  void _showStatusSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context:       context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TaskStatusSheet(task: task),
    );
  }

  String _statusLabel(String s) => switch (s) {
    'in_progress' => 'In Progress',
    'completed'   => 'Completed',
    'cancelled'   => 'Cancelled',
    _             => 'Pending',
  };
}

// ─────────────────────────────────────────────
// Bottom sheet for full status update
// ─────────────────────────────────────────────

class _TaskStatusSheet extends ConsumerStatefulWidget {
  const _TaskStatusSheet({required this.task});
  final TasksTableData task;

  @override
  ConsumerState<_TaskStatusSheet> createState() => _TaskStatusSheetState();
}

class _TaskStatusSheetState extends ConsumerState<_TaskStatusSheet> {
  late TaskStatus _selected;
  final _hoursCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = TaskStatusX.fromApi(widget.task.status);
    if (widget.task.actualHours != null) {
      _hoursCtrl.text = widget.task.actualHours.toString();
    }
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(widget.task.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Status options
            const Text('Update Status',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 10),

            ...TaskStatus.values
                .where((s) => s != TaskStatus.cancelled)
                .map((s) => RadioListTile<TaskStatus>(
                  value: s,
                  groupValue: _selected,
                  title: Text(_label(s)),
                  activeColor: taskStatusColor(s.apiValue),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _selected = v!),
                )),

            // Actual hours — shown when completing
            if (_selected == TaskStatus.completed) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _hoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Actual hours worked',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final hours = _selected == TaskStatus.completed
        ? double.tryParse(_hoursCtrl.text) : null;

    await ref.read(taskActionsProvider).updateStatus(
      task:        widget.task,
      newStatus:   _selected,
      actualHours: hours,
    );
    if (mounted) Navigator.pop(context);
  }

  String _label(TaskStatus s) => switch (s) {
    TaskStatus.pending    => 'Pending',
    TaskStatus.inProgress => 'In Progress',
    TaskStatus.completed  => 'Completed',
    TaskStatus.cancelled  => 'Cancelled',
  };
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
