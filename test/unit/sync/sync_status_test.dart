import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/sync/sync_service.dart';

void main() {
  group('SyncStatus defaults', () {
    test('isSyncing is false', () => expect(const SyncStatus().isSyncing, false));
    test('pendingCount is 0', () => expect(const SyncStatus().pendingCount, 0));
    test('lastError is null', () => expect(const SyncStatus().lastError, isNull));
  });

  group('SyncStatus.copyWith', () {
    test('updates isSyncing, preserves others', () {
      const s = SyncStatus(pendingCount: 3);
      final updated = s.copyWith(isSyncing: true);
      expect(updated.isSyncing, true);
      expect(updated.pendingCount, 3);
      expect(updated.lastError, isNull);
    });

    test('updates pendingCount, preserves others', () {
      const s = SyncStatus(isSyncing: true);
      final updated = s.copyWith(pendingCount: 7);
      expect(updated.pendingCount, 7);
      expect(updated.isSyncing, true);
    });

    test('sets lastError', () {
      const s = SyncStatus();
      final updated = s.copyWith(lastError: 'network timeout');
      expect(updated.lastError, 'network timeout');
    });

    test('no args preserves all fields', () {
      const s = SyncStatus(isSyncing: true, pendingCount: 5);
      final updated = s.copyWith();
      expect(updated.isSyncing, true);
      expect(updated.pendingCount, 5);
    });
  });
}

