import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/research/application/research_authority_lifecycle.dart';
import 'package:vocab_learning_app/features/research/application/research_transport_consent_coordinator.dart';
import 'package:vocab_learning_app/features/research/data/http_research_authority_gateway.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/ed25519_research_permit_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Python-signed HTTP context and consent acknowledgement admit both actual SQLite caches',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final empty = await f.status();
      expect(empty.accepted, isFalse);
      expect(
        (await ownerMigrationRows(f.database))['research_consents'],
        isEmpty,
      );
      expect(await f.coordinator.accept(empty), isTrue);
      final accepted = await f.status();
      expect(accepted.decidedAtUtc, f.serverNow);
      expect(accepted.decidedAtUtc, isNot(f.localNow));
      final context = await f.coordinator.loadEnrollment();
      final gate = ResearchAuthorityReadGate();
      final caches = [
        for (final assessment in [false, true])
          LocalResearchAuthorityCache(
            ownerWrites: f.ownerWrites,
            currentScope: () => f.binding == null
                ? null
                : context.scope(binding: f.binding!, assessment: assessment),
            gateway: f.transport,
            operationSignatures: Ed25519ResearchPermitSignatureVerifier({
              for (final entry
                  in (f.fixture['operationPublicKeysBase64'] as Map).entries)
                entry.key as String: base64.decode(entry.value as String),
            }),
            participationSignatures: ResearchP256SignatureVerifier(
              publicKeysSec1Hex: Map<String, String>.from(
                f.fixture['participationPublicKeysSec1Hex'] as Map,
              ),
            ),
            generateRequestId: () =>
                'synthetic-refresh-${assessment ? 'assessment' : 'motivation'}',
            maximumAcceptedAge: const Duration(minutes: 10),
            initiallyForeground: true,
            readGate: gate,
            monotonicElapsed: () => f.elapsed,
          ),
      ];
      final lifecycle = ResearchAuthorityLifecycle(
        caches: caches,
        readGate: gate,
        reconcileBeforeRefresh: f.coordinator.reconcileBeforeRefresh,
        initiallyForeground: true,
      );
      addTearDown(lifecycle.dispose);
      final before = await ownerMigrationRows(f.database);
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      for (final cache in caches) {
        expect(await cache.read(), isNotNull);
        expect(
          await cache.loadPermit(
            ownerId: f.ownerId,
            operation: ResearchOperation.collect,
          ),
          isNotNull,
        );
      }
      expect(await ownerMigrationRows(f.database), before);
      expect(before['events_v2'], isEmpty);
      expect(before['outbox_operations'], isEmpty);
    },
  );

  test('missing enrollment leaves every research table empty', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.enrolled = false;
    final before = await ownerMigrationRows(f.database);
    await expectLater(
      f.coordinator.accept(await f.status()),
      throwsA(
        isA<ResearchTransportException>().having(
          (error) => error.code,
          'code',
          ResearchTransportFailureCode.notEnrolled,
        ),
      ),
    );
    await expectLater(
      f.coordinator.withdraw(await f.status(), f.localNow),
      throwsA(isA<ResearchTransportException>()),
    );
    expect(await ownerMigrationRows(f.database), before);
  });

  test(
    'legacy version-one acceptance cannot acknowledge a remote supplied notice or create an owner',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final empty = AppDatabase(NativeDatabase.memory());
      addTearDown(empty.close);
      final repository = DriftResearchConsentRepository(empty);
      final remote = ResearchTransportConsentCoordinator(
        repository: repository,
        gateway: f.transport,
        currentBinding: () => f.binding,
        invalidateAuthority: () {},
        generateRequestId: () => 'synthetic-legacy',
        version: 1,
      );
      addTearDown(remote.dispose);
      var generatedOwners = 0;
      final useCases = ResearchConsentUseCases(
        repository: repository,
        remoteDecisions: remote,
        owners: DriftLocalOwnerRepository(
          empty,
          generateId: () {
            generatedOwners++;
            return 'synthetic-unexpected';
          },
          nowUtc: () => f.localNow,
        ),
        nowUtc: () => f.localNow,
      );
      final before = await ownerMigrationRows(empty);
      expect(await useCases.accept(), isFalse);
      expect(await ownerMigrationRows(empty), before);
      expect(generatedOwners, 0);
      expect(f.requests, isEmpty);
    },
  );

  test(
    'server acknowledgement mirrors an existing local timestamp without replacing its row identity',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.database
          .into(f.database.researchConsents)
          .insert(
            ResearchConsentsCompanion.insert(
              id: 'synthetic-historical-row',
              ownerId: f.ownerId,
              consentVersion: 1,
              consentState: 'accepted',
              decidedAtUtcMs: f.localNow.millisecondsSinceEpoch,
            ),
          );
      expect(await f.coordinator.accept(await f.status()), isTrue);
      final row = await f.database
          .select(f.database.researchConsents)
          .getSingle();
      expect(row.id, 'synthetic-historical-row');
      expect(row.decidedAtUtcMs, f.serverNow.millisecondsSinceEpoch);
    },
  );

  test(
    'withdrawal commits a local terminal barrier before a failed server call and reconciles after restart',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.coordinator.accept(await f.status()), isTrue);
      f.failWithdrawal = true;
      await expectLater(
        f.coordinator.withdraw(await f.status(), f.localNow),
        throwsA(
          isA<ResearchTransportException>().having(
            (error) => error.code,
            'code',
            ResearchTransportFailureCode.withdrawalPending,
          ),
        ),
      );
      final barrier = await f.status();
      expect(barrier.accepted, isFalse);
      expect(barrier.withdrawnAtUtc, f.localNow);
      expect(await f.coordinator.accept(barrier), isFalse);
      f.coordinator.dispose();
      f.coordinator = f.newCoordinator();
      f.failWithdrawal = false;
      expect(await f.coordinator.reconcileBeforeRefresh(), isFalse);
      final acknowledged = await f.status();
      expect(acknowledged.decidedAtUtc, f.serverNow);
      expect(
        acknowledged.withdrawnAtUtc,
        f.serverNow.add(const Duration(minutes: 1)),
      );
      expect(await f.coordinator.accept(acknowledged), isFalse);
    },
  );

  test('late acceptance acknowledgement cannot replace withdrawal', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    f.acceptPaused = Completer<http.Response>();
    final initial = await f.status();
    final accepting = f.coordinator.accept(initial);
    final acceptedFailure = expectLater(
      accepting,
      throwsA(isA<ResearchTransportException>()),
    );
    await f.acceptRequested.future;
    expect(await f.coordinator.withdraw(initial, f.localNow), isTrue);
    final barrier = await f.status();
    f.acceptPaused!.complete(f.acceptReply!);
    await acceptedFailure;
    expect((await f.status()).sameFacts(barrier), isTrue);
  });

  test(
    'owner A-B-A during token acquisition admits no request or consent row',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final token = Completer<String?>();
      f.token = () => token.future;
      final before = await ownerMigrationRows(f.database);
      final accepting = f.coordinator.accept(await f.status());
      final rejected = expectLater(
        accepting,
        throwsA(isA<ResearchTransportException>()),
      );
      await Future<void>.delayed(Duration.zero);
      f.binding = ResearchAuthorityBinding(
        ownerId: 'synthetic-other-owner',
        authSubjectId: 'synthetic-other-uid',
        generation: 2,
      );
      f.binding = ResearchAuthorityBinding(
        ownerId: f.ownerId,
        authSubjectId: f.uid,
        generation: 3,
      );
      token.complete('synthetic-token');
      await rejected;
      expect(f.requests, isEmpty);
      expect(await ownerMigrationRows(f.database), before);
    },
  );

  test(
    'deletion and ambient transaction boundaries reject authoritative mirrors',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final expected = await f.status();
      final acknowledged = ResearchConsentStatus(
        ownerId: f.ownerId,
        version: 1,
        accepted: true,
        decidedAtUtc: f.serverNow,
      );
      await f.database.transaction(() async {
        expect(
          await f.repository.mirrorAcknowledgement(
            expected: expected,
            acknowledged: acknowledged,
            authSubjectId: f.uid,
            stillCurrent: () => true,
          ),
          isFalse,
        );
      });
      await f.ownerWrites.beginDeletion(
        ownerId: f.ownerId,
        firebaseUid: f.uid,
        idempotencyKey: 'synthetic-research-delete',
      );
      final before = await ownerMigrationRows(f.database);
      await expectLater(
        f.repository.mirrorAcknowledgement(
          expected: expected,
          acknowledged: acknowledged,
          authSubjectId: f.uid,
          stillCurrent: () => true,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await ownerMigrationRows(f.database), before);
    },
  );

  test(
    'paired lifecycle hides the first cache while the second is pending and invalidates both on failure',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      expect(await f.coordinator.accept(await f.status()), isTrue);
      final context = await f.coordinator.loadEnrollment();
      final gate = ResearchAuthorityReadGate();
      final caches = _newCaches(f, context, gate);
      final changes = StreamController<Object?>.broadcast(sync: true);
      addTearDown(changes.close);
      final lifecycle = ResearchAuthorityLifecycle(
        caches: caches,
        readGate: gate,
        invalidations: [changes.stream],
        initiallyForeground: true,
        onUnprovenInterval: f.coordinator.retirePending,
      );
      addTearDown(lifecycle.dispose);
      f.assessmentRequested = Completer<void>();
      f.assessmentRelease = Completer<void>();
      var callerCurrent = true;
      final refreshing = lifecycle.refresh(stillCurrent: () => callerCurrent);
      await f.assessmentRequested!.future;
      expect(caches.first.hasFreshSnapshot, isTrue);
      expect(await caches.first.read(), isNull);
      expect(await caches.last.read(), isNull);
      expect(gate.isOpen, isFalse);
      f.assessmentRelease!.complete();
      expect(await refreshing, isTrue);
      callerCurrent = false;
      expect(
        await caches.first.read(),
        isNotNull,
        reason: 'Acknowledged authority survives closing the refresh page',
      );
      f.assessmentRelease = null;
      f.failAssessment = true;
      expect(await lifecycle.refresh(stillCurrent: () => true), isFalse);
      expect(caches.every((cache) => !cache.hasFreshSnapshot), isTrue);
      expect(gate.isOpen, isFalse);
      f.failAssessment = false;
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      changes.add(null);
      expect(await caches.first.read(), isNull);
      expect(await caches.last.read(), isNull);
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(await caches.first.read(), isNull);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(await caches.first.read(), isNull);
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      f.binding = ResearchAuthorityBinding(
        ownerId: f.ownerId,
        authSubjectId: f.uid,
        generation: 3,
      );
      expect(await caches.first.read(), isNull);
      expect(await caches.last.read(), isNull);
    },
  );

  test('the same instrument twice cannot claim a current pair', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    expect(await f.coordinator.accept(await f.status()), isTrue);
    final context = await f.coordinator.loadEnrollment();
    final gate = ResearchAuthorityReadGate();
    final caches = _newCaches(f, context, gate, repeatMotivation: true);
    final lifecycle = ResearchAuthorityLifecycle(
      caches: caches,
      readGate: gate,
      initiallyForeground: true,
    );
    addTearDown(lifecycle.dispose);
    expect(await lifecycle.refresh(stillCurrent: () => true), isFalse);
    expect(await caches.first.read(), isNull);
    expect(await caches.last.read(), isNull);
  });
}

List<LocalResearchAuthorityCache> _newCaches(
  _Fixture f,
  ResearchEnrollmentContext context,
  ResearchAuthorityReadGate gate, {
  bool repeatMotivation = false,
}) => [
  for (final assessment in [false, true])
    LocalResearchAuthorityCache(
      ownerWrites: f.ownerWrites,
      currentScope: () => f.binding == null
          ? null
          : context.scope(
              binding: f.binding!,
              assessment: assessment && !repeatMotivation,
            ),
      gateway: f.transport,
      operationSignatures: Ed25519ResearchPermitSignatureVerifier({
        for (final entry
            in (f.fixture['operationPublicKeysBase64'] as Map).entries)
          entry.key as String: base64.decode(entry.value as String),
      }),
      participationSignatures: ResearchP256SignatureVerifier(
        publicKeysSec1Hex: Map<String, String>.from(
          f.fixture['participationPublicKeysSec1Hex'] as Map,
        ),
      ),
      generateRequestId: () =>
          'synthetic-pair-${assessment ? 'assessment' : 'motivation'}',
      maximumAcceptedAge: const Duration(minutes: 5),
      initiallyForeground: true,
      readGate: gate,
      monotonicElapsed: () => f.elapsed,
    ),
];

final class _Fixture {
  _Fixture(this.database, this.fixture);
  final AppDatabase database;
  final Map<String, dynamic> fixture;
  late final DriftOwnerWriteCoordinator ownerWrites;
  late final DriftResearchConsentRepository repository;
  late final HttpResearchTransport transport;
  late final http.Client client;
  late ResearchTransportConsentCoordinator coordinator;
  late ResearchAuthorityBinding? binding;
  final serverNow = DateTime.utc(2026, 11, 1, 12);
  final localNow = DateTime.utc(2030, 1, 1);
  Duration elapsed = Duration.zero;
  bool enrolled = true;
  bool serverAccepted = false;
  bool serverWithdrawn = false;
  bool failWithdrawal = false;
  int invalidations = 0;
  int _request = 0;
  final requests = <String>[];
  Future<String?> Function()? token;
  Completer<http.Response>? acceptPaused;
  final acceptRequested = Completer<void>();
  http.Response? acceptReply;
  Completer<void>? assessmentRequested;
  Completer<void>? assessmentRelease;
  bool failAssessment = false;
  Map<String, dynamic> get enrollment =>
      fixture['enrollment'] as Map<String, dynamic>;
  String get ownerId => enrollment['ownerId'] as String;
  String get uid => enrollment['firebaseUid'] as String;

  static Future<_Fixture> open() async {
    final fixture =
        jsonDecode(
              File(
                'backend/ai_api/tests/fixtures/research_server_wire_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(fixture['synthetic'], isTrue);
    final f = _Fixture(AppDatabase(NativeDatabase.memory()), fixture);
    await f.database
        .into(f.database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: f.ownerId,
            firebaseUid: Value(f.uid),
            accountState: const Value('firebaseBound'),
            createdAtUtcMs: 1,
            isActive: const Value(true),
          ),
        );
    f.binding = ResearchAuthorityBinding(
      ownerId: f.ownerId,
      authSubjectId: f.uid,
      generation: 1,
    );
    f.ownerWrites = DriftOwnerWriteCoordinator(
      f.database,
      nowUtc: () => f.localNow,
    );
    f.repository = DriftResearchConsentRepository(
      f.database,
      ownerWrites: f.ownerWrites,
    );
    f.client = MockClient(f.respond);
    f.transport = HttpResearchTransport(
      client: f.client,
      baseUri: Uri.parse('https://synthetic-research.example'),
      currentBinding: () => f.binding,
      loadIdToken: (_) => f.token?.call() ?? Future.value('synthetic-token'),
    );
    f.coordinator = f.newCoordinator();
    return f;
  }

  ResearchTransportConsentCoordinator newCoordinator() =>
      ResearchTransportConsentCoordinator(
        repository: repository,
        gateway: transport,
        currentBinding: () => binding,
        invalidateAuthority: () => invalidations++,
        generateRequestId: () => 'synthetic-consent-${_request++}',
        version: 1,
      );

  Future<ResearchConsentStatus> status() =>
      repository.load(ownerId: ownerId, version: 1);

  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> respond(http.Request request) async {
    requests.add(request.url.path);
    if (!enrolled) return reply({}, 404);
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path.endsWith('enrollment-context')) {
      return reply({
        'schemaVersion': 1,
        'enrollmentId': enrollment['enrollmentId'],
        'ownerId': ownerId,
        'authSubjectId': uid,
        'consentVersion': 1,
        'protocolVersion': enrollment['protocolVersion'],
        'scopes': [
          for (final scope in enrollment['scopes'] as List)
            {'role': scope['role'], 'requirements': scope['requirements']},
        ],
      });
    }
    if (request.url.path.endsWith('/consent')) {
      final accepted = body!['decision'] == 'accepted';
      if (!accepted) {
        final local = await status();
        expect(
          local.withdrawnAtUtc,
          isNotNull,
          reason: 'Local denial precedes external withdrawal',
        );
        if (failWithdrawal) throw const SocketException('synthetic offline');
        serverWithdrawn = true;
      } else if (!serverWithdrawn) {
        serverAccepted = true;
      }
      final response = reply({
        'schemaVersion': 1,
        'enrollmentId': enrollment['enrollmentId'],
        'ownerId': ownerId,
        'consentVersion': 1,
        'requestId': body['requestId'],
        'state': serverWithdrawn ? 'withdrawn' : 'accepted',
        'receiptId': enrollment['consentReceiptId'],
        'revision': serverWithdrawn ? 2 : 1,
        'decidedAtUtc': serverAccepted ? serverNow.toIso8601String() : null,
        'withdrawnAtUtc': serverWithdrawn
            ? serverNow.add(const Duration(minutes: 1)).toIso8601String()
            : null,
      });
      if (accepted && acceptPaused != null) {
        acceptReply = response;
        if (!acceptRequested.isCompleted) acceptRequested.complete();
        return acceptPaused!.future;
      }
      return response;
    }
    if (request.url.path.endsWith('/refresh')) {
      if (!serverAccepted || serverWithdrawn) return reply({}, 403);
      final scope =
          (enrollment['scopes'] as List).singleWhere(
                (scope) =>
                    scope['requirements']['instrumentId'] ==
                    body!['scope']['requirements']['instrumentId'],
              )
              as Map;
      if (scope['role'] == 'assessment') {
        if (assessmentRequested?.isCompleted == false) {
          assessmentRequested!.complete();
        }
        await assessmentRelease?.future;
        if (failAssessment) return reply({}, 503);
      }
      return reply({
        'schemaVersion': 1,
        'scope': body!['scope'],
        'requestId': body['requestId'],
        'clockSessionId': body['clockSessionId'],
        'monotonicEpoch': body['monotonicEpoch'],
        'snapshotRevision': 1,
        'anchorUtc': serverNow.toIso8601String(),
        'validUntilUtc': serverNow
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'maximumAgeMs': 300000,
        'operationDocuments': scope['operationDocuments'],
        'operationStates': scope['operationStates'],
        'participationDocuments': scope['participationDocuments'],
        'receipts': [
          for (final receipt in scope['receipts'] as List)
            {...receipt as Map, 'decidedAtUtc': serverNow.toIso8601String()},
        ],
      });
    }
    return reply({}, 404);
  }

  Future<void> close() async {
    coordinator.dispose();
    client.close();
    await database.close();
  }
}
