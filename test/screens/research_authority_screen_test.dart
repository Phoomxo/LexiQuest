import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/application/research_authority_lifecycle.dart';
import 'package:vocab_learning_app/features/research/application/research_transport_consent_coordinator.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/ed25519_research_permit_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/features/research/presentation/research_authority_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'missing supplied notice disables acknowledgement at320px200percent ${brightness.name}',
      (tester) async {
        final f = (await tester.runAsync(_Fixture.open))!;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2),
                  viewInsets: EdgeInsets.only(bottom: 180),
                ),
                child: ResearchAuthorityScreen(
                  consent: f.consent,
                  authority: f.authority,
                ),
              ),
            ),
          );
          final accept = find.byKey(
            const ValueKey('research-authority-accept'),
          );
          await _until(
            tester,
            () =>
                f.gateway.contextReads > 0 &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty,
          );
          await tester.scrollUntilVisible(accept, 200, maxScrolls: 20);
          await tester.ensureVisible(accept);
          expect(tester.widget<FilledButton>(accept).onPressed, isNull);
          expect(f.gateway.decisions, 0);
          expect(
            (await tester.runAsync(
              () => f.database.select(f.database.researchConsents).get(),
            ))!,
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(f.close);
        }
      },
    );
  }

  testWidgets(
    'explicit supplied notice acknowledgement stores server time and idle owner replacement hides it',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      try {
        await tester.pumpWidget(f.app());
        await _until(
          tester,
          () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
        );
        final accept = find.byKey(const ValueKey('research-authority-accept'));
        expect(tester.widget<FilledButton>(accept).onPressed, isNull);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await _until(
          tester,
          () => find
              .text('เซิร์ฟเวอร์ยืนยันการตัดสินใจแล้ว')
              .evaluate()
              .isNotEmpty,
        );
        final stored = (await tester.runAsync(
          () => f.database.select(f.database.researchConsents).getSingle(),
        ))!;
        expect(stored.decidedAtUtcMs, f.gateway.now.millisecondsSinceEpoch);
        expect(f.gateway.decisions, 1);
        f.binding = ResearchAuthorityBinding(
          ownerId: 'synthetic-other-owner',
          authSubjectId: 'synthetic-other-uid',
          generation: 2,
        );
        f.bindings.add(f.binding);
        await tester.pump();
        expect(find.text('Synthetic supplied Study notice'), findsNothing);
        expect(find.text('เซิร์ฟเวอร์ยืนยันการตัดสินใจแล้ว'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.close);
      }
    },
  );

  testWidgets(
    'lost acceptance acknowledgement can be withdrawn before any local acceptance exists',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      f.gateway.loseAcceptanceAcknowledgementOnce = true;
      try {
        await tester.pumpWidget(f.app());
        await _until(
          tester,
          () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        final accept = find.byKey(const ValueKey('research-authority-accept'));
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await _until(
          tester,
          () => find
              .text('ยังยืนยันสิทธิ์ Study ไม่ได้ การเรียนทั่วไปยังใช้ได้')
              .evaluate()
              .isNotEmpty,
        );
        expect(f.gateway.acceptedOnServer, isTrue);
        expect(f.gateway.decisions, 1);
        expect(
          (await tester.runAsync(
            () => f.database.select(f.database.researchConsents).get(),
          ))!,
          isEmpty,
        );
        final withdraw = find.byKey(
          const ValueKey('research-authority-withdraw'),
        );
        expect(withdraw, findsOneWidget);
        await tester.ensureVisible(withdraw);
        await tester.tap(withdraw);
        await _until(
          tester,
          () => find.text('เซิร์ฟเวอร์ยืนยันการถอนแล้ว').evaluate().isNotEmpty,
        );
        final stored = (await tester.runAsync(
          () => f.database.select(f.database.researchConsents).getSingle(),
        ))!;
        expect(stored.consentState, 'withdrawn');
        expect(stored.decidedAtUtcMs, f.gateway.now.millisecondsSinceEpoch);
        expect(stored.withdrawnAtUtcMs, f.gateway.now.millisecondsSinceEpoch);
        expect(f.gateway.withdrawnOnServer, isTrue);
        expect(f.gateway.decisions, 2);
        await tester.ensureVisible(accept);
        expect(tester.widget<FilledButton>(accept).onPressed, isNull);
        for (final table in [
          'experiment_assignments',
          'research_participation_permits',
          'events_v2',
          'outbox_operations',
        ]) {
          expect(
            (await tester.runAsync(
              () => f.database
                  .customSelect('SELECT COUNT(*) AS n FROM "$table"')
                  .getSingle(),
            ))!.read<int>('n'),
            0,
            reason: table,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.close);
      }
    },
  );

  testWidgets(
    'leaving during enrollment confirmation cannot send a consent decision',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      try {
        await tester.pumpWidget(f.app());
        await _until(
          tester,
          () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
        );
        f.gateway.pendingContext = Completer<ResearchEnrollmentContext>();
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        final accept = find.byKey(const ValueKey('research-authority-accept'));
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        f.gateway.pendingContext!.complete(f.gateway.context);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(f.gateway.decisions, 0);
        expect(
          (await tester.runAsync(
            () => f.database.select(f.database.researchConsents).get(),
          ))!,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.close);
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var count = 0; count < 100; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (done()) return;
  }
  fail('Synthetic authority UI did not reach its acknowledged state');
}

final class _Fixture {
  _Fixture(this.database);
  final AppDatabase database;
  final gateway = _Enrollment();
  final bindings = StreamController<ResearchAuthorityBinding?>.broadcast(
    sync: true,
  );
  ResearchAuthorityBinding? binding = ResearchAuthorityBinding(
    ownerId: 'synthetic-owner',
    authSubjectId: 'synthetic-uid',
    generation: 1,
  );
  late final ResearchTransportConsentCoordinator consent;
  late final ResearchAuthorityLifecycle authority;

  static Future<_Fixture> open() async {
    final f = _Fixture(AppDatabase(NativeDatabase.memory()));
    await f.database
        .into(f.database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'synthetic-owner',
            firebaseUid: const Value('synthetic-uid'),
            accountState: const Value('firebaseBound'),
            isActive: const Value(true),
            createdAtUtcMs: 1,
          ),
        );
    final writes = DriftOwnerWriteCoordinator(
      f.database,
      nowUtc: () => DateTime.utc(2030),
    );
    final repository = DriftResearchConsentRepository(
      f.database,
      ownerWrites: writes,
    );
    final gate = ResearchAuthorityReadGate();
    final caches = [
      for (final assessment in [false, true])
        LocalResearchAuthorityCache(
          ownerWrites: writes,
          currentScope: () => f.binding == null
              ? null
              : f.gateway.context.scope(
                  binding: f.binding!,
                  assessment: assessment,
                ),
          gateway: _UnavailableAuthority(),
          operationSignatures: Ed25519ResearchPermitSignatureVerifier({}),
          participationSignatures: ResearchP256SignatureVerifier(
            publicKeysSec1Hex: {},
          ),
          generateRequestId: () => 'synthetic-refresh',
          maximumAcceptedAge: const Duration(minutes: 5),
          initiallyForeground: true,
          readGate: gate,
        ),
    ];
    f.consent = ResearchTransportConsentCoordinator(
      repository: repository,
      gateway: f.gateway,
      currentBinding: () => f.binding,
      bindingChanges: f.bindings.stream,
      invalidateAuthority: () => f.authority.invalidate(),
      generateRequestId: () => 'synthetic-decision',
      version: 1,
    );
    f.authority = ResearchAuthorityLifecycle(
      caches: caches,
      readGate: gate,
      onUnprovenInterval: f.consent.retirePending,
      initiallyForeground: true,
    );
    return f;
  }

  Widget app() => MaterialApp(
    home: ResearchAuthorityScreen(
      consent: consent,
      authority: authority,
      notice: SuppliedResearchConsentNotice(
        version: 1,
        protocolVersion: 'synthetic-protocol-v1',
        title: 'Synthetic supplied Study notice',
        body: 'Synthetic test information only. No real study authority.',
      ),
      nowUtc: () => DateTime.utc(2030),
    ),
  );

  Future<void> close() async {
    consent.dispose();
    await authority.dispose();
    await bindings.close();
    await database.close();
  }
}

final class _UnavailableAuthority implements ResearchAuthorityGateway {
  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async => null;
}

final class _Enrollment implements ResearchEnrollmentGateway {
  int decisions = 0;
  int contextReads = 0;
  bool loseAcceptanceAcknowledgementOnce = false;
  bool acceptedOnServer = false;
  bool withdrawnOnServer = false;
  final now = DateTime.utc(2026, 11, 1);
  Completer<ResearchEnrollmentContext>? pendingContext;
  ResearchPermitRequirements pins(String instrument) =>
      ResearchPermitRequirements(
        supportedFormatVersion: 1,
        trustedIssuerId: 'synthetic-issuer',
        trustedIssuerKeyId: 'synthetic-ed',
        signatureAlgorithm: 'EdDSA',
        assignmentId: 'synthetic-assignment',
        assignmentRevision: 1,
        protocolId: 'synthetic-protocol',
        protocolRevision: 1,
        instrumentId: instrument,
        instrumentRevision: 1,
      );
  ResearchEnrollmentContext get context => ResearchEnrollmentContext(
    enrollmentId: 'synthetic-enrollment',
    ownerId: 'synthetic-owner',
    authSubjectId: 'synthetic-uid',
    consentVersion: 1,
    protocolVersion: 'synthetic-protocol-v1',
    motivationRequirements: pins('synthetic-motivation'),
    assessmentRequirements: pins('synthetic-assessment'),
  );
  @override
  Future<ResearchEnrollmentContext> loadEnrollment(
    ResearchAuthorityBinding binding, {
    required bool Function() stillCurrent,
  }) async {
    contextReads++;
    return pendingContext?.future ?? context;
  }

  @override
  Future<ResearchConsentAcknowledgement> decideConsent({
    required ResearchAuthorityBinding binding,
    required ResearchEnrollmentContext enrollment,
    required bool accepted,
    required String requestId,
    required bool Function() stillCurrent,
  }) async {
    decisions++;
    if (accepted && !withdrawnOnServer) acceptedOnServer = true;
    if (!accepted) withdrawnOnServer = true;
    if (accepted && loseAcceptanceAcknowledgementOnce) {
      loseAcceptanceAcknowledgementOnce = false;
      throw const ResearchTransportException(
        ResearchTransportFailureCode.unavailable,
      );
    }
    return ResearchConsentAcknowledgement(
      enrollmentId: enrollment.enrollmentId,
      ownerId: binding.ownerId,
      version: 1,
      requestId: requestId,
      accepted: acceptedOnServer && !withdrawnOnServer,
      receiptId: 'synthetic-consent',
      revision: 1,
      decidedAtUtc: now,
      withdrawnAtUtc: withdrawnOnServer ? now : null,
    );
  }
}
