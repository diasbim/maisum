class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.baseDelay = const Duration(seconds: 20),
    this.maxDelay = const Duration(minutes: 5),
  });

  final Duration baseDelay;
  final Duration maxDelay;

  DateTime nextAttempt({required int retryCount, DateTime? now}) {
    final exponent = retryCount.clamp(0, 6);
    var delay = baseDelay * (1 << exponent);
    if (delay > maxDelay) {
      delay = maxDelay;
    }
    return (now ?? DateTime.now()).add(delay);
  }
}
