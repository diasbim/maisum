import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../app/providers.dart';
import 'sync_service.dart';

class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    final service = ref.watch(syncServiceProvider);
    return ref.watch(syncStatusStreamProvider).valueOrNull ?? service.status;
  }

  Future<void> sync() => ref.read(syncServiceProvider).processQueue();

  Future<void> retryFailed({String? itemId}) =>
      ref.read(syncServiceProvider).retryFailed(itemId: itemId);
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

final syncStatusProvider = Provider<SyncStatus>(
  (ref) => ref.watch(syncControllerProvider),
);
