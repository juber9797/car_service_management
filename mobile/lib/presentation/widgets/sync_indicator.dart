import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:car_workshop/core/sync/sync_engine.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';

class SyncIndicatorButton extends ConsumerWidget {
  const SyncIndicatorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState   = ref.watch(syncStateProvider).valueOrNull;
    final pendingCount = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    final icon = switch (syncState) {
      SyncState.syncing => const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white)),
      SyncState.error => const Icon(Icons.sync_problem, color: AppColors.warning),
      _ => Icon(
          pendingCount > 0 ? Icons.sync_outlined : Icons.cloud_done_outlined,
          color: pendingCount > 0 ? AppColors.caution : Colors.white,
        ),
    };

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: icon,
          tooltip: pendingCount > 0
              ? '$pendingCount change(s) pending sync'
              : 'All synced',
          onPressed: () {}, // could show a sync details bottom sheet
        ),
        if (pendingCount > 0)
          Positioned(
            top: 8, right: 8,
            child: Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(
                  color: AppColors.caution, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  pendingCount > 9 ? '9+' : '$pendingCount',
                  style: const TextStyle(
                      fontSize: 8, color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
