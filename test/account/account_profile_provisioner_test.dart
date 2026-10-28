import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';

final class _RecordingProfileWriter implements AccountProfileWriter {
  final writes = <({String uid, AccountProfile profile, bool merge})>[];
  final completedUids = <String>{};
  Object? lookupError;

  @override
  Future<void> writeProfile({
    required String uid,
    required AccountProfile profile,
    required bool merge,
  }) async {
    writes.add((uid: uid, profile: profile, merge: merge));
  }

  @override
  Future<bool> isProvisioningComplete(String uid) async {
    final error = lookupError;
    if (error != null) throw error;
    return completedUids.contains(uid);
  }

  @override
  Future<void> markProvisioningComplete(String uid) async {
    completedUids.add(uid);
  }
}

final class _MemoryCompletionStore
    implements AccountProvisioningCompletionStore {
  final completedUids = <String>{};

  @override
  Future<bool> isComplete(String uid) async => completedUids.contains(uid);

  @override
  Future<void> markComplete(String uid) async {
    completedUids.add(uid);
  }
}

final class _PartiallyFailingDefaultCategories
    implements DefaultCategoryProvisioner {
  bool failFirstAttempt = true;
  final categoryIds = <String>{};

  @override
  Future<void> ensureDefaults(String uid) async {
    categoryIds.add('$uid:animals');
    if (failFirstAttempt) {
      failFirstAttempt = false;
      throw StateError('interrupted-default-category-write');
    }
    categoryIds.add('$uid:travel');
  }
}

void main() {
  test(
    'partial default category provisioning converges before completion',
    () async {
      final writer = _RecordingProfileWriter();
      final categories = _PartiallyFailingDefaultCategories();
      final completionStore = _MemoryCompletionStore();
      final provisioner = AccountProfileProvisioner(
        profileWriter: writer,
        defaultCategoryProvisioner: categories,
        completionStore: completionStore,
      );
      const profile = AccountProfile(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: ' Ada@Example.COM ',
        age: 20,
      );

      await expectLater(
        provisioner.ensureProfile('student-1', profile),
        throwsStateError,
      );
      expect(
        await provisioner.provisioningState('student-1'),
        AccountProvisioningState.incomplete,
      );

      await provisioner.ensureProfile('student-1', profile);

      expect(writer.writes, hasLength(2));
      expect(writer.writes.map((write) => write.merge), everyElement(isTrue));
      expect(
        writer.writes.map((write) => write.profile.normalizedEmail),
        everyElement('ada@example.com'),
      );
      expect(categories.categoryIds, {'student-1:animals', 'student-1:travel'});
      expect(
        await provisioner.provisioningState('student-1'),
        AccountProvisioningState.complete,
      );
      expect(completionStore.completedUids, contains('student-1'));
    },
  );

  test(
    'durable completion permits offline access after remote success',
    () async {
      final writer = _RecordingProfileWriter();
      final completionStore = _MemoryCompletionStore();
      final provisioner = AccountProfileProvisioner(
        profileWriter: writer,
        defaultCategoryProvisioner: _PartiallyFailingDefaultCategories()
          ..failFirstAttempt = false,
        completionStore: completionStore,
      );
      const profile = AccountProfile(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        age: 20,
      );

      await provisioner.ensureProfile('student-1', profile);
      writer.lookupError = StateError('offline');

      expect(
        await provisioner.provisioningState('student-1'),
        AccountProvisioningState.complete,
      );
    },
  );

  test(
    'remote failure without durable completion remains unavailable',
    () async {
      final writer = _RecordingProfileWriter()
        ..lookupError = StateError('offline');
      final provisioner = AccountProfileProvisioner(
        profileWriter: writer,
        defaultCategoryProvisioner: _PartiallyFailingDefaultCategories(),
        completionStore: _MemoryCompletionStore(),
      );

      expect(
        await provisioner.provisioningState('unknown-student'),
        AccountProvisioningState.unavailable,
      );
    },
  );

  test(
    'restored remote incomplete result overrides stale local completion',
    () async {
      final writer = _RecordingProfileWriter();
      final completionStore = _MemoryCompletionStore()
        ..completedUids.add('student-1');
      final provisioner = AccountProfileProvisioner(
        profileWriter: writer,
        defaultCategoryProvisioner: _PartiallyFailingDefaultCategories(),
        completionStore: completionStore,
      );

      expect(
        await provisioner.provisioningState('student-1'),
        AccountProvisioningState.incomplete,
      );
    },
  );

  test(
    'shared preferences completion survives a new store instance per uid',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firstStore = SharedPreferencesAccountProvisioningCompletionStore();
      await firstStore.markComplete('student-1');

      final restoredStore =
          SharedPreferencesAccountProvisioningCompletionStore();
      expect(await restoredStore.isComplete('student-1'), isTrue);
      expect(await restoredStore.isComplete('student-2'), isFalse);
    },
  );
}
