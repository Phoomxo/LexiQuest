import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/adventure_research_runtime_config.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/research/application/adventure_research_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import '../../support/motivation_research_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  late AdventureResearchRuntime runtime;
  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize();
    runtime = AdventureResearchRuntime(
      participation: f.participation,
      measurements: f.measurements,
      opportunities: DriftMeasurementOpportunityRepository(
        f.database,
        measurements: f.measurements,
        nowUtc: () => f.now,
      ),
      consent: DriftResearchConsentRepository(f.database),
    );
  });
  tearDown(() => f.database.close());
  test('production default composes no research runtime', () {
    expect(
      AdventureResearchRuntime.fromConfig(
        f.database,
        const AdventureResearchRuntimeConfig.off(),
        nowUtc: () => f.now,
      ),
      isNull,
    );
  });
  test(
    'deferred receipt provider binds once to the exact runtime database',
    () {
      var calls = 0;
      final configured = AdventureResearchRuntimeConfig.configured(
        study: f.study,
        issuerPublicKeys: {'synthetic': '04${'0' * 128}'},
        createReceipts: (database) {
          calls++;
          expect(database, same(f.database));
          return f.authority;
        },
      );
      final composed = AdventureResearchRuntime.fromConfig(
        f.database,
        configured,
        nowUtc: () => f.now,
      )!;
      expect(calls, 1);
      expect(composed.participation.validator.receipts, same(f.authority));
      expect(composed.participation.database, same(f.database));
    },
  );
  test(
    'mutation hook observes committed capture and withdrawal, and queue failure cannot undo either',
    () async {
      final observed = <String>[];
      runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
        onLocalMutation: (ownerId) async {
          expect(ownerId, 'owner:a');
          final rows = await f.database
              .select(f.database.motivationMeasurementRuns)
              .get();
          observed.add(rows.single.state);
          throw StateError('synthetic queue unavailable');
        },
      );
      final run = await runtime.useCases.prepare(
        ownerId: 'owner:a',
        permitId: 'permit:a',
      );
      expect(run, isNotNull);
      expect(observed, ['started']);
      await runtime.useCases.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run!.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      );
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        hasLength(1),
      );
      await runtime.withdraw('owner:a');
      expect(observed, ['started', 'started', 'withdrawn']);
      expect(await runtime.currentPermit('owner:a'), isNull);
    },
  );
  test(
    'configured factory uses real P256, never fixture signature authority',
    () async {
      final composed = AdventureResearchRuntime.fromConfig(
        f.database,
        AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: {'synthetic': '04${'0' * 128}'},
          receipts: f.authority,
        ),
        nowUtc: () => f.now,
      )!;
      expect(
        composed.participation.validator.signatures,
        isA<ResearchP256SignatureVerifier>(),
      );
      expect(await composed.currentPermit('owner:a'), isNull);
    },
  );
  test(
    'configured runtime adapts a real precision clock to research milliseconds',
    () async {
      final raw = f.now.add(const Duration(microseconds: 321));
      final composed = AdventureResearchRuntime.fromConfig(
        f.database,
        AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: {'synthetic': '04${'0' * 128}'},
          receipts: f.authority,
        ),
        nowUtc: () => raw,
      )!;
      expect(composed.participation.nowUtc(), f.now);
      expect(composed.measurements.nowUtc(), f.now);
      expect(composed.opportunities.nowUtc(), f.now);
      // No real permit is needed to withdraw. A valid system clock must not make
      // local withdrawal throw before reaching the consent transaction.
      await composed.withdraw('owner:a');
      expect(
        (await f.database.select(f.database.researchConsents).get())
            .single
            .consentState,
        'withdrawn',
      );
    },
  );
  test(
    'document import is idempotent, owner-bound, and never manufactures consent',
    () async {
      final p = f.permit();
      final document = jsonEncode({
        ...jsonDecode(p.canonicalPayload()) as Map<String, dynamic>,
        'payloadSha256': p.payloadSha256,
        'signature': p.signature,
      });
      await runtime.importDocument('owner:a', document);
      await runtime.importDocument('owner:a', document);
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        hasLength(1),
      );
      await expectLater(
        runtime.importDocument('owner:other', document),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      await runtime.withdraw('owner:a');
      await expectLater(
        runtime.importDocument('owner:a', document),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await runtime.currentPermit('owner:a'), isNull);
    },
  );
  test(
    'withdraw keeps existing answers and signature but closes capture',
    () async {
      final run = (await runtime.useCases.prepare(
        ownerId: 'owner:a',
        permitId: 'permit:a',
      ))!;
      await f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      );
      final signature =
          (await f.database
                  .select(f.database.researchParticipationPermits)
                  .get())
              .single
              .signature;
      await runtime.withdraw('owner:a');
      expect(
        (await f.database.select(f.database.motivationMeasurementRuns).get())
            .single
            .state,
        'withdrawn',
      );
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        hasLength(1),
      );
      expect(
        (await f.database.select(f.database.researchParticipationPermits).get())
            .single
            .signature,
        signature,
      );
      expect(await runtime.currentPermit('owner:a'), isNull);
    },
  );
}
