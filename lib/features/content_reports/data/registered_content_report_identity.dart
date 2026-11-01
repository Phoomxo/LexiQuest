import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../billing/billing_runtime.dart';
import '../../billing/domain/billing_contracts.dart';
import '../domain/content_report.dart';
import '../domain/content_report_transport.dart';

Future<ContentReportIdentityPorts> createRegisteredContentReportIdentity({
  required DriftBillingAccountBinding accounts,
  required Future<String?> Function(BillingAccount) loadIdToken,
}) async {
  var generation = 0;
  var disposed = false;
  var retired = false;
  ContentReportIdentityBinding? observed;
  ContentReportIdentityBinding? current() {
    final account = accounts.currentAccount;
    final binding = observed;
    return !disposed &&
            !retired &&
            account != null &&
            binding != null &&
            account.ownerId == binding.ownerId &&
            account.firebaseUid == binding.firebaseUid
        ? binding
        : null;
  }

  void changed(BillingAccount? account) {
    generation++;
    observed = null;
    if (!disposed && !retired && account != null && !account.isAnonymous) {
      try {
        observed = ContentReportIdentityBinding(
          ownerId: account.ownerId,
          firebaseUid: account.firebaseUid,
          generation: generation,
        );
      } on ArgumentError {
        observed = null;
      }
    }
  }

  void retire() {
    changed(null);
    retired = true;
  }

  final subscription = accounts.changes.listen(
    changed,
    onError: (Object _) => retire(),
    onDone: retire,
  );
  void requireBinding(ContentReportIdentityBinding binding) {
    if (current() != binding) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
  }

  Future<void> requireCurrent(ContentReportIdentityBinding binding) async {
    requireBinding(binding);
    final account = accounts.currentAccount!;
    try {
      await accounts.requireCurrent(account);
    } on Object {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
    requireBinding(binding);
  }

  Future<void>? disposal;
  Future<void> close() async {
    disposed = true;
    observed = null;
    generation++;
    await subscription.cancel();
    await accounts.dispose();
  }

  Future<void> dispose() => disposal ??= close();
  try {
    await accounts.refresh();
    return ContentReportIdentityPorts(
      currentBinding: current,
      requireCurrent: requireCurrent,
      loadIdToken: (binding) async {
        await requireCurrent(binding);
        final account = accounts.currentAccount!;
        final token = await loadIdToken(account);
        await requireCurrent(binding);
        return token;
      },
      dispose: dispose,
    );
  } on Object {
    await dispose();
    rethrow;
  }
}

Future<String?> contentReportFirebaseIdToken(
  FirebaseAuth auth,
  BillingAccount account,
) async {
  final user = auth.currentUser;
  if (user == null || user.isAnonymous || user.uid != account.firebaseUid) {
    return null;
  }
  final token = await user.getIdToken();
  final after = auth.currentUser;
  return after != null && !after.isAnonymous && after.uid == user.uid
      ? token
      : null;
}
