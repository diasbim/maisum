import '../domain/sync_item.dart';

class SyncProjectionException implements Exception {
  const SyncProjectionException(this.entityType, this.cause);

  final String entityType;
  final Object cause;

  @override
  String toString() =>
      'Não foi possível guardar localmente a confirmação de $entityType.';
}

/// A feature's own half of the queue's outcome.
///
/// [SyncService] knows how to send an operation, when to retry it and when to
/// give up; it deliberately does not know what a referral sale or a
/// provisional affiliate is. A projection is how a feature says what to write
/// when the server answers, without either side importing the other's tables.
///
/// There is exactly one queue and one processor. This is not a second sync
/// engine: it is called from inside the existing one, on the item the existing
/// one just processed, in the same pass.
abstract interface class SyncProjection {
  /// The queue `entity_type` values this projection owns.
  Set<String> get entityTypes;

  /// Writes the server's canonical answer for [item].
  ///
  /// Returns the canonical entity id when it differs from the queued one, so
  /// the caller can mark the right row synced — the same contract
  /// `SyncProcessResult.canonicalEntity` already has for recovery tasks.
  Future<String?> applyCanonical(
    SyncItem item,
    Map<String, dynamic> canonical,
  );

  /// Records that [item] will not be sent again.
  ///
  /// Only called once the queue has stopped trying, so what it writes is a
  /// terminal state a person has to see rather than a transient error that a
  /// later attempt would clear.
  Future<void> applyFailure(SyncItem item, {required String reason});

  /// Refreshes whatever read cache this feature needs for offline work.
  ///
  /// Runs once per successful sync pass, after the pulls. A failure here is
  /// never allowed to fail the sync: a stale cache costs a discount, a failed
  /// sync costs every queued sale.
  Future<void> refreshReadCaches();
}
