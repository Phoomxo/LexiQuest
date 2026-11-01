import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/application/research_transport_consent_coordinator.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import '../../support/assessment_authority_harness.dart';
import '../../support/research_transport_composition_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final offline in [false, true]) {
    test(
      offline
          ? 'questionnaire withdrawal attempts server reconciliation while offline and stops collection locally'
          : 'questionnaire withdrawal reaches the authoritative server without a later refresh',
      () async {
        final source = await AssessmentAuthorityFixture.open();
        final harness = SyntheticResearchCompositionHarness(
          source: source,
          store: _NoWriteStore(),
        );
        final context = source.study.runtime.context;
        final composition = await harness.create(
          ResearchTransportFactoryContext(
            study: context,
            baseUri: Uri.https('synthetic-research.invalid'),
          ),
        );
        final gateway = _WithdrawalGateway(harness.gateway, offline: offline);
        var request = 0;
        final consent = ResearchTransportConsentCoordinator(
          repository: context.consentRepository,
          gateway: gateway,
          currentBinding: () => harness.binding,
          bindingChanges: harness.bindingChanges.stream,
          invalidateAuthority: composition.lifecycle.invalidate,
          generateRequestId: () => 'synthetic-withdrawal-${++request}',
          version: composition.consent.version,
        );
        addTearDown(() async {
          consent.dispose();
          await composition.dispose();
          await source.close();
        });
        final runtime = LocalStudyRuntime(
          context: context,
          authorities: composition.studyRuntime.authorities,
          catalog: composition.studyRuntime.catalog,
          assessmentFactory: () => composition.studyRuntime.assessment,
          remoteConsentDecisions: consent,
        );
        source.study.runtime = runtime;
        source.study.bindLearning();
        expect(
          await composition.lifecycle.refresh(stillCurrent: () => true),
          isTrue,
        );
        final run = (await runtime.begin('owner-a')).run!;
        expect(run.state, MotivationMeasurementRunState.started);
        final repository = runtime.measurementsFor('owner-a');
        source.study.participation.clock.now = source
            .study
            .participation
            .clock
            .now
            .add(const Duration(minutes: 1));

        MotivationMeasurementRun? acknowledged;
        try {
          acknowledged = await repository.close(
            MotivationMeasurementClose(
              ownerId: 'owner-a',
              runId: run.id,
              state: MotivationMeasurementRunState.withdrawn,
            ),
          );
        } on ResearchTransportException catch (error) {
          expect(offline, isTrue);
          expect(error.code, ResearchTransportFailureCode.withdrawalPending);
        }
        expect(gateway.withdrawalAttempts, 1);
        expect(gateway.serverWithdrawn, !offline);
        if (!offline) {
          expect(acknowledged!.state, MotivationMeasurementRunState.withdrawn);
        } else if (acknowledged != null) {
          expect(acknowledged.state, MotivationMeasurementRunState.withdrawn);
        }
        final local = await context.consentRepository.load(
          ownerId: 'owner-a',
          version: consent.version,
        );
        expect(local.accepted, isFalse);
        expect(local.withdrawnAtUtc, isNotNull);
        final before = await source.study.researchRows();
        await expectLater(
          repository.record(
            MotivationResponse(
              ownerId: 'owner-a',
              runId: run.id,
              itemId: 'synthetic-baseline',
              responseCode: 'high',
            ),
          ),
          throwsA(isA<ResearchCaptureDenied>()),
        );
        expect(await source.study.researchRows(), before);
      },
    );
  }
}

final class _WithdrawalGateway implements ResearchEnrollmentGateway {
  _WithdrawalGateway(this.inner, {required this.offline});
  final ResearchEnrollmentGateway inner;
  final bool offline;
  int withdrawalAttempts = 0;
  bool serverWithdrawn = false;

  @override
  Future<ResearchEnrollmentContext> loadEnrollment(
    ResearchAuthorityBinding binding, {
    required bool Function() stillCurrent,
  }) => inner.loadEnrollment(binding, stillCurrent: stillCurrent);

  @override
  Future<ResearchConsentAcknowledgement> decideConsent({
    required ResearchAuthorityBinding binding,
    required ResearchEnrollmentContext enrollment,
    required bool accepted,
    required String requestId,
    required bool Function() stillCurrent,
  }) async {
    expect(accepted, isFalse);
    expect(stillCurrent(), isTrue);
    withdrawalAttempts++;
    if (offline) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.unavailable,
      );
    }
    final result = await inner.decideConsent(
      binding: binding,
      enrollment: enrollment,
      accepted: accepted,
      requestId: requestId,
      stillCurrent: stillCurrent,
    );
    serverWithdrawn = !result.accepted && result.withdrawnAtUtc != null;
    return result;
  }
}

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required Future<void> Function() revalidateBeforeWrite,
  }) => throw StateError('The withdrawal fixture never writes an archive');
}
