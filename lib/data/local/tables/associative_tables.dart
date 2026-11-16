import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Drift tables for the Associative Learning domain.
///
/// Schema v10 — added in Phase 2 D8.3.
///
/// Two tables back the [AssociativeLearningPort] contract:
///   - [AssociationRecords]      — keyword/story/image cues per word
///   - [AssociativeMemoryStates] — per-word algorithm state for the
///                                  AdaptiveAssociativeScheduler

// ─── AssociationRecords ───────────────────────────────────────────────────────

/// A memory association created by the learner for a vocabulary word.
///
/// Each row is a (owner, wordKey, type) triple — one association per
/// association type per word per owner.  The content is replaced on update.
class AssociationRecords extends Table {
  TextColumn get id => text()();

  TextColumn get ownerId => text().references(LocalOwners, #id)();

  /// The vocabulary word identifier (may be a Drift word ID or a plain
  /// display string for the associative reading prototype).
  TextColumn get wordKey => text()();

  /// Association type: `'keyword'`, `'story'`, `'image_url'`, etc.
  TextColumn get type => text()();

  /// The association content (keyword phrase, story text, URL).
  TextColumn get content => text()();

  IntColumn get createdAtUtcMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  /// One association per (owner, word, type) — upsert replaces existing.
  @override
  List<Set<Column>> get uniqueKeys => [
    {ownerId, wordKey, type},
  ];
}

// ─── AssociativeMemoryStates ──────────────────────────────────────────────────

/// Per-word associative-memory algorithm state for one owner.
///
/// Mirrors [AssociativeMemoryState] from [learning_layer_adapter.dart].
/// One row per (owner, wordKey); updated by [AdaptiveAssociativeScheduler]
/// after each recall attempt.
class AssociativeMemoryStates extends Table {
  TextColumn get id => text()();

  TextColumn get ownerId => text().references(LocalOwners, #id)();

  TextColumn get wordKey => text()();

  RealColumn get stability => real().withDefault(const Constant(1.0))();
  RealColumn get difficulty => real().withDefault(const Constant(5.0))();
  RealColumn get cueDependency => real().withDefault(const Constant(0.0))();

  IntColumn get lapseCount => integer().withDefault(const Constant(0))();

  IntColumn get lastReviewedAtUtcMs => integer().nullable()();
  IntColumn get nextDueAtUtcMs => integer()();

  /// Algorithm version string, e.g. `'v1.0.0'`.
  TextColumn get algorithmVersion => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {ownerId, wordKey},
  ];
}
