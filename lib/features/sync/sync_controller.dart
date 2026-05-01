import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../app/providers.dart';
import 'sync_service.dart';

class SyncController extends Notifier<SyncStatus> {
  StreamSubscription<SyncStatus>? _sub;

  @override
  SyncStatus build() {
    final service = ref.watch(syncServiceProvider);
    _sub?.cancel();
    _sub = service.statusStream.listen((s) => state = s);
    ref.onDispose(() => _sub?.cancel());
    return service.status;
  }

  Future<void> sync() => ref.read(syncServiceProvider).processQueue();
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);
