import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../features/billing/billing_runtime.dart';
import '../features/billing/domain/billing_contracts.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/domain/research_authority_snapshot.dart';
import '../features/research/domain/research_transport_contracts.dart';
import 'configured_research_transport_factory.dart';

Future<ResearchTransportIdentityPorts> createRegisteredResearchIdentity({
  required DriftBillingAccountBinding accounts,
  required Future<String?> Function(BillingAccount account) loadIdToken,
}) async {
  final changes = StreamController<ResearchAuthorityBinding?>.broadcast(
    sync: true,
  );
  ResearchAuthorityBinding? observed;
  var generation = 0;
  var disposed = false;
  var observerRetired = false;
  Future<void>? disposal;

  ResearchAuthorityBinding? current() {
    final account = accounts.currentAccount;
    final binding = observed;
    return !disposed &&
            !observerRetired &&
            account != null &&
            binding != null &&
            account.ownerId == binding.ownerId &&
            account.firebaseUid == binding.authSubjectId
        ? binding
        : null;
  }

  void changed(BillingAccount? account) {
    if (disposed || observerRetired) return;
    generation++;
    observed = null;
    if (account != null) {
      try {
        observed = ResearchAuthorityBinding(
          ownerId: account.ownerId,
          authSubjectId: account.firebaseUid,
          generation: generation,
        );
      } on FormatException {
        observed = null;
      }
    }
    changes.add(current());
  }

  void retire() {
    if (disposed || observerRetired) return;
    changed(null);
    observerRetired = true;
  }

  final subscription = accounts.changes.listen(
    changed,
    onError: (Object _) => retire(),
    onDone: retire,
  );
  Future<void> close() async {
    disposed = true;
    observed = null;
    changes.add(null);
    try {
      await subscription.cancel();
      await accounts.dispose();
    } finally {
      await changes.close();
    }
  }

  Future<void> dispose() => disposal ??= close();

  void require(ResearchAuthorityBinding binding) {
    if (current() != binding) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.ownerChanged,
      );
    }
  }

  try {
    await accounts.refresh();
    return ResearchTransportIdentityPorts(
      currentBinding: current,
      bindingChanges: changes.stream,
      loadIdToken: (binding) async {
        require(binding);
        final account = accounts.currentAccount!;
        await accounts.requireCurrent(account);
        require(binding);
        final token = await loadIdToken(account);
        require(binding);
        await accounts.requireCurrent(account);
        require(binding);
        return token;
      },
      dispose: dispose,
    );
  } on Object {
    await dispose();
    rethrow;
  }
}

Future<ResearchTransportIdentityPorts> createFirebaseResearchIdentity(
  StudyRuntimeContext context, {
  required FirebaseAuth auth,
}) => createRegisteredResearchIdentity(
  accounts: DriftBillingAccountBinding(
    database: context.database,
    currentIdentity: () {
      final user = auth.currentUser;
      return user == null
          ? null
          : BillingAuthIdentity(uid: user.uid, isAnonymous: user.isAnonymous);
    },
    authInvalidations: auth.authStateChanges().map<void>((_) {}),
  ),
  loadIdToken: (account) async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous || user.uid != account.firebaseUid) {
      return null;
    }
    final token = await user.getIdToken();
    final after = auth.currentUser;
    return after != null && !after.isAnonymous && after.uid == user.uid
        ? token
        : null;
  },
);
