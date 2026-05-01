import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum SyncState { idle, syncing, pending, error }

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.state, this.pendingCount = 0});

  final SyncState state;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      SyncState.syncing => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.onPrimary,
          ),
        ),
      SyncState.pending => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.syncPending,
                shape: BoxShape.circle,
              ),
            ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$pendingCount',
                style: const TextStyle(color: AppColors.onPrimary, fontSize: 12),
              ),
            ],
          ],
        ),
      SyncState.error => const Icon(Icons.sync_problem, size: 18, color: AppColors.error),
      SyncState.idle => Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.syncDone,
            shape: BoxShape.circle,
          ),
        ),
    };
  }
}
