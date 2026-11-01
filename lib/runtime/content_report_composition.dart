import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../features/billing/billing_runtime.dart';
import '../features/content_reports/application/content_report_use_cases.dart';
import '../features/content_reports/data/drift_content_report_queue.dart';
import '../features/content_reports/data/http_content_report_transport.dart';
import '../features/content_reports/data/registered_content_report_identity.dart';
import '../features/identity/data/drift_owner_write_coordinator.dart';

final class ContentReportComposition {
  const ContentReportComposition({
    required this.useCases,
    required this.dispose,
  });
  final ContentReportUseCases useCases;
  final Future<void> Function() dispose;
}

Future<ContentReportComposition> createProductionContentReports({
  required AppDatabase database,
  required Uri baseUri,
  required FirebaseAuth auth,
}) async {
  final accounts = DriftBillingAccountBinding(
    database: database,
    currentIdentity: () {
      final user = auth.currentUser;
      return user == null
          ? null
          : BillingAuthIdentity(uid: user.uid, isAnonymous: user.isAnonymous);
    },
    authInvalidations: auth.userChanges().map((_) {}),
  );
  final identity = await createRegisteredContentReportIdentity(
    accounts: accounts,
    loadIdToken: (account) => contentReportFirebaseIdToken(auth, account),
  );
  final client = http.Client();
  final queue = DriftContentReportQueue(
    database: database,
    ownerWrites: DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => DateTime.now().toUtc(),
    ),
  );
  return ContentReportComposition(
    useCases: ContentReportUseCases(
      queue: queue,
      ordinarySessionGuard: queue.requireOrdinarySession,
      generateId: const Uuid().v4,
      nowUtc: () => DateTime.now().toUtc(),
      transport: HttpContentReportTransport(
        client: client,
        baseUri: baseUri,
        identity: identity,
        enabled: true,
      ),
    ),
    dispose: () async {
      client.close();
      await identity.dispose();
    },
  );
}
