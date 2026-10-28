import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_gateway.dart';
import 'account_validation.dart';
import '../services/category_service.dart';

final class AccountProfile {
  const AccountProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.age,
  });

  final String firstName;
  final String lastName;
  final String email;
  final int age;

  String get normalizedEmail => AccountValidation.normalizeEmail(email);
}

abstract interface class AccountProfileProvisioning {
  Future<void> ensureProfile(String uid, AccountProfile profile);
  Future<AccountProvisioningState> provisioningState(String uid);
}

enum AccountProvisioningState { complete, incomplete, unavailable }

abstract interface class AccountProfileWriter {
  Future<void> writeProfile({
    required String uid,
    required AccountProfile profile,
    required bool merge,
  });
  Future<void> markProvisioningComplete(String uid);
  Future<bool> isProvisioningComplete(String uid);
}

abstract interface class AccountProvisioningCompletionStore {
  Future<bool> isComplete(String uid);
  Future<void> markComplete(String uid);
}

abstract interface class DefaultCategoryProvisioner {
  Future<void> ensureDefaults(String uid);
}

final class AccountProfileProvisioner implements AccountProfileProvisioning {
  AccountProfileProvisioner({
    AccountProfileWriter? profileWriter,
    DefaultCategoryProvisioner? defaultCategoryProvisioner,
    AccountProvisioningCompletionStore? completionStore,
  }) : _profileWriter = profileWriter ?? FirestoreAccountProfileWriter(),
       _defaultCategoryProvisioner =
           defaultCategoryProvisioner ??
           CategoryServiceDefaultCategoryProvisioner(),
       _completionStore =
           completionStore ??
           SharedPreferencesAccountProvisioningCompletionStore();

  final AccountProfileWriter _profileWriter;
  final DefaultCategoryProvisioner _defaultCategoryProvisioner;
  final AccountProvisioningCompletionStore _completionStore;

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) async {
    await _profileWriter.writeProfile(uid: uid, profile: profile, merge: true);
    await _defaultCategoryProvisioner.ensureDefaults(uid);
    await _profileWriter.markProvisioningComplete(uid);
    await _completionStore.markComplete(uid);
  }

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async {
    try {
      final complete = await _profileWriter.isProvisioningComplete(uid);
      if (!complete) return AccountProvisioningState.incomplete;
      try {
        await _completionStore.markComplete(uid);
      } on Object {
        // The current remote result is authoritative for this launch. A later
        // offline launch remains unavailable until the durable write succeeds.
      }
      return AccountProvisioningState.complete;
    } on Object {
      try {
        return await _completionStore.isComplete(uid)
            ? AccountProvisioningState.complete
            : AccountProvisioningState.unavailable;
      } on Object {
        return AccountProvisioningState.unavailable;
      }
    }
  }
}

final class UnavailableAccountProfileProvisioner
    implements AccountProfileProvisioning {
  const UnavailableAccountProfileProvisioner();

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) =>
      Future<void>.error(
        const AccountOperationException('profile-provisioning-unavailable'),
      );

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async =>
      AccountProvisioningState.unavailable;
}

final class SharedPreferencesAccountProvisioningCompletionStore
    implements AccountProvisioningCompletionStore {
  SharedPreferencesAccountProvisioningCompletionStore({
    Future<SharedPreferences> Function()? getPreferences,
  }) : _getPreferences = getPreferences ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'account.provisioning.complete.';
  final Future<SharedPreferences> Function() _getPreferences;

  @override
  Future<bool> isComplete(String uid) async =>
      (await _getPreferences()).getBool('$_keyPrefix$uid') == true;

  @override
  Future<void> markComplete(String uid) async {
    final saved = await (await _getPreferences()).setBool(
      '$_keyPrefix$uid',
      true,
    );
    if (!saved) {
      throw StateError('account-provisioning-completion-write-failed');
    }
  }
}

final class FirestoreAccountProfileWriter implements AccountProfileWriter {
  FirestoreAccountProfileWriter({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> writeProfile({
    required String uid,
    required AccountProfile profile,
    required bool merge,
  }) async {
    final reference = _firestore.collection('users').doc(uid);
    final existing = await reference.get();
    final data = <String, Object?>{
      'first_name': profile.firstName.trim(),
      'last_name': profile.lastName.trim(),
      'email': profile.normalizedEmail,
      'age': profile.age,
      'profileSchemaVersion': 1,
      'requiredProvisioningComplete': false,
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await reference.set(data, SetOptions(merge: merge));
  }

  @override
  Future<void> markProvisioningComplete(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .set({'requiredProvisioningComplete': true}, SetOptions(merge: true));

  @override
  Future<bool> isProvisioningComplete(String uid) async {
    final profile = await _firestore.collection('users').doc(uid).get();
    return profile.data()?['requiredProvisioningComplete'] == true;
  }
}

final class CategoryServiceDefaultCategoryProvisioner
    implements DefaultCategoryProvisioner {
  CategoryServiceDefaultCategoryProvisioner({CategoryService? categoryService})
    : _categoryService = categoryService ?? CategoryService();

  final CategoryService _categoryService;

  @override
  Future<void> ensureDefaults(String uid) =>
      _categoryService.addDefaultCategoriesForNewUser(uid);
}
