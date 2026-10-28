import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../learning_packs/domain/content_manifest.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_personal_learning_profile_reader.dart';
import '../data/drift_progress_queries.dart';
import '../domain/personal_learning_profile.dart';
import '../domain/progress_models.dart';

typedef ProgressUtcNow = DateTime Function();

final class ProgressUseCases {
  const ProgressUseCases({
    required this.owners,
    required this.queries,
    required this.nowUtc,
    this.profileReader,
    this.learningTimezoneId = 'Asia/Bangkok',
  });

  final LocalOwnerRepository owners;
  final DriftProgressQueries queries;
  final ProgressUtcNow nowUtc;
  final DriftPersonalLearningProfileReader? profileReader;
  final String learningTimezoneId;

  Future<PackProgressSnapshot> loadPack(ContentIdentity identity) async {
    final owner = await owners.getOrCreateActiveOwner();
    return queries.loadPack(ownerId: owner.id, identity: identity);
  }

  Future<ProgressSnapshot> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    return loadForOwner(owner.id);
  }

  Future<ProgressSnapshot> loadForOwner(String ownerId) async {
    if (ownerId.isEmpty || ownerId.trim() != ownerId) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    return queries.load(ownerId: ownerId, nowUtc: now);
  }

  /// Observes committed owner changes through the same owner authority as loads.
  Stream<({String ownerId, String? firebaseUid})?> watchProfileOwner() {
    final database = queries.database;
    return Stream<({String ownerId, String? firebaseUid})?>.multi((sink) {
      var cancelled = false;
      var revision = 0;
      Future<void> refresh() async {
        final request = ++revision;
        try {
          final owner = await owners.getOrCreateActiveOwner();
          if (!cancelled && request == revision) {
            sink.add((ownerId: owner.id, firebaseUid: owner.firebaseUid));
          }
        } catch (error, stack) {
          if (!cancelled && request == revision) sink.addError(error, stack);
        }
      }

      // Subscribe before the first read so a concurrent transition cannot fall
      // between the initial snapshot and the change listener. Superseded reads
      // are discarded; no retained query stream is created for this signal.
      final updates = database
          .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
          .listen((_) => unawaited(refresh()), onError: sink.addError);
      sink.onCancel = () {
        cancelled = true;
        return updates.cancel();
      };
      unawaited(refresh());
    }).distinct();
  }

  Future<PersonalLearningProfile> loadPersonalLearningProfile() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final reader =
        profileReader ??
        DriftPersonalLearningProfileReader(queries.database, progress: queries);
    return reader.load(
      ownerId: owner.id,
      nowUtc: now,
      timezoneId: learningTimezoneId,
    );
  }
}
