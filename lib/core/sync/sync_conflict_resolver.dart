class SyncConflictResolver {
  const SyncConflictResolver();

  Map<String, dynamic> resolve({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required String updatedAtField,
  }) {
    final localUpdated = local[updatedAtField] as int? ?? 0;
    final remoteUpdated = remote[updatedAtField] as int? ?? 0;

    if (remoteUpdated >= localUpdated) {
      return remote;
    }
    return local;
  }
}
