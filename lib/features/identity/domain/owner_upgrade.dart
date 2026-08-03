enum OwnerUpgradeMode {
  anonymousBound,
  mergedExisting,
  alreadyBound,
  localGuestCreated,
}

final class OwnerUpgradeResult {
  const OwnerUpgradeResult({
    required this.targetOwnerId,
    required this.mode,
    required this.conflictCount,
  });

  final String targetOwnerId;
  final OwnerUpgradeMode mode;
  final int conflictCount;
}

abstract interface class OwnerUpgradeRepository {
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  });

  Future<OwnerUpgradeResult> createLocalGuestAfterLogout();

  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  });
}

const Set<String> ownerUpgradeInventory = <String>{
  'research_consents',
  'vocabulary_categories',
  'vocabulary_words',
  'vocabulary_imports',
  'learning_sessions',
  'answer_attempts',
  'srs_states',
  'reading_progress_entries',
  'reading_events',
  'points_ledger_entries',
  'achievement_unlocks',
  'reward_transactions',
  'owned_reward_items',
  'equipped_reward_items',
  'outbox_operations',
  'sync_checkpoints',
  'sync_conflicts',
  'events_v2',
};
