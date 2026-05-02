import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';

const _uuid = Uuid();

class AddTaskScreen extends ConsumerStatefulWidget {
  const AddTaskScreen({super.key, required this.jobCardId});
  final String jobCardId;

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _hoursCtrl    = TextEditingController();
  final _rateCtrl     = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final user   = ref.read(currentUserProvider)!;
      final dao    = ref.read(jobCardDaoProvider);
      final engine = ref.read(syncEngineProvider);

      final taskId = _uuid.v4();
      final now    = DateTime.now();

      // 1. Write to local DB immediately (optimistic)
      await dao.upsertTask(TasksTableCompanion(
        id:            Value(taskId),
        garageId:      Value(user.garageId),
        jobCardId:     Value(widget.jobCardId),
        title:         Value(_titleCtrl.text.trim()),
        description:   Value(_descCtrl.text.trim().isEmpty
                         ? null : _descCtrl.text.trim()),
        status:        const Value('pending'),
        estimatedHours: Value(double.tryParse(_hoursCtrl.text)),
        laborRate:     Value(double.tryParse(_rateCtrl.text)),
        version:       const Value(1),
        createdAt:     Value(now),
        updatedAt:     Value(now),
      ));

      // 2. Enqueue for server sync
      await engine.enqueueChange(
        entityType: 'tasks',
        entityId:   taskId,
        operation:  SyncOperation.create,
        payload: {
          'jobCardId':      widget.jobCardId,
          'title':          _titleCtrl.text.trim(),
          'description':    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'estimatedHours': double.tryParse(_hoursCtrl.text),
          'laborRate':      double.tryParse(_rateCtrl.text),
        },
        baseVersion: 0,
      );

      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Task')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Task Title *',
                hintText: 'e.g. Replace brake pads',
                prefixIcon: Icon(Icons.task_alt_outlined),
              ),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional details...',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hoursCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Est. Hours',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Labor Rate/hr',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Task'),
            ),
          ],
        ),
      ),
    );
  }
}
