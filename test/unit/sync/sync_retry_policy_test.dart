import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/sync/sync_retry_policy.dart';

void main() {
  group('SyncRetryPolicy', () {
    const policy = SyncRetryPolicy(
      baseDelay: Duration(seconds: 10),
      maxDelay: Duration(minutes: 5),
    );

    test('increases delay with retries', () {
      final now = DateTime(2026, 5, 13, 10, 0);
      final first = policy.nextAttempt(retryCount: 1, now: now);
      final second = policy.nextAttempt(retryCount: 2, now: now);

      expect(first.difference(now), const Duration(seconds: 20));
      expect(second.difference(now), const Duration(seconds: 40));
    });
  });
}
