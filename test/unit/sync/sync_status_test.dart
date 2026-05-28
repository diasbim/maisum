import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/sync/sync_service.dart';

void main() {
  group('SyncStatus defaults', () {
    test(
      'isSyncing is false',
      () => expect(const SyncStatus(isOnline: true).isSyncing, false),
    );
    test(
      'pendingCount is 0',
      () => expect(const SyncStatus(isOnline: true).pendingCount, 0),
    );
    test(
      'lastError is null',
      () => expect(const SyncStatus(isOnline: true).lastError, isNull),
    );
  });

  group('SyncStatus.copyWith', () {
    test('updates isSyncing, preserves others', () {
      const s = SyncStatus(isOnline: true, pendingCount: 3);
      final updated = s.copyWith(phase: SyncPhase.syncing);
      expect(updated.isSyncing, true);
      expect(updated.pendingCount, 3);
      expect(updated.lastError, isNull);
    });

    test('updates pendingCount, preserves others', () {
      const s = SyncStatus(isOnline: true, phase: SyncPhase.syncing);
      final updated = s.copyWith(pendingCount: 7);
      expect(updated.pendingCount, 7);
      expect(updated.isSyncing, true);
    });

    test('sets lastError', () {
      const s = SyncStatus(isOnline: true);
      final updated = s.copyWith(lastError: 'network timeout');
      expect(updated.lastError, 'network timeout');
    });

    test('no args preserves all fields', () {
      const s = SyncStatus(
        isOnline: true,
        phase: SyncPhase.syncing,
        pendingCount: 5,
      );
      final updated = s.copyWith();
      expect(updated.isSyncing, true);
      expect(updated.pendingCount, 5);
    });
  });
}
