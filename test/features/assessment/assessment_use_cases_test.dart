import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

import 'support/assessment_application_harness.dart';

void main() {
  late AssessmentRun run;
  late SyntheticAssessmentRepository repository;
  late SyntheticContentAuthority content;
  late AssessmentUseCases useCases;
  var visible = true;
  bool stillVisible() => visible;
  setUp(() {
    run = syntheticRun();
    repository = SyntheticAssessmentRepository([run]);
    final definition = syntheticDefinition();
    content = SyntheticContentAuthority(definition);
    useCases = AssessmentUseCases(
      repository: repository,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [definition]),
      contentAuthority: content,
    );
    visible = true;
  });

  Future<AssessmentPresentation> begin() => useCases.beginPresentation(
    syntheticStart(run),
    ownerId: run.ownerId,
    stillVisible: stillVisible,
  );
  Future<AssessmentSubmissionReceipt> submit({
    String itemId = 'synthetic-item-b',
    String option = 'A choice',
    int latency = 250,
  }) => useCases.submitPresentedResponse(
    ownerId: run.ownerId,
    runId: run.id,
    itemId: itemId,
    option: option,
    responseTimeMs: latency,
    stillVisible: stillVisible,
  );

  test(
    'presentation preserves canonical items and sorts controlled option keys',
    () async {
      final presentation = await begin();
      expect(presentation.run, same(run));
      expect(presentation.items.map((item) => item.itemId), [
        'synthetic-item-b',
        'synthetic-item-a',
      ]);
      expect(presentation.items.first.options, ['A choice', 'Z choice']);
      expect(presentation.answeredItemIds, isEmpty);
      expect(repository.calls.single['command'], isA<AssessmentStartCommand>());
      expect(repository.calls.single['ownerId'], run.ownerId);
      expect(repository.presentationChecks, 1);
    },
  );

  test(
    'presentation rehydrates exact stored item evidence without scoring UI',
    () async {
      repository.evidence[run.learningSessionId] = [syntheticEvidence(run, 0)];
      final presentation = await begin();
      expect(presentation.answeredItemIds, {'synthetic-item-b'});
      expect(
        () => presentation.answeredItemIds.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'phase or authority invalidated after durable start denies question display',
    () async {
      repository.beforeReturn = () => repository.denyPresentation = true;
      await expectLater(begin(), throwsStateError);
      expect(repository.presentationChecks, 1);
    },
  );

  test(
    'foreign run and mismatched start identity cannot become a presentation',
    () async {
      for (final changes in [
        {'ownerId': 'foreign-owner'},
        {'learningSessionId': 'foreign-session'},
        {'studyCycleId': 'foreign-cycle'},
        {'instrumentChecksumSha256': 'b' * 64},
      ]) {
        repository.runs[0] = syntheticRun(changes: changes);
        await expectLater(begin(), throwsStateError);
      }
    },
  );

  test('malformed durable evidence cannot mark an item answered', () async {
    repository.evidence[run.learningSessionId] = [
      syntheticEvidence(
        run,
        0,
        changes: {'sourceEvidenceId': 'foreign-source'},
      ),
    ];
    await expectLater(begin(), throwsStateError);
  });

  test(
    'content identity and exact bytes are required before writer start',
    () async {
      content.returned = AssessmentVerifiedFormContent(
        identity: AssessmentFormContentIdentity(
          formId: 'other-form',
          revision: 7,
        ),
        checksumSha256: content.definition.formChecksumSha256,
        bytes: content.definition.formBytes,
      );
      await expectLater(begin(), throwsStateError);
      expect(repository.calls, isEmpty);
    },
  );

  test('hidden entry and visibility loss during awaits fail closed', () async {
    visible = false;
    await expectLater(begin(), throwsStateError);
    expect(repository.calls, isEmpty);
    visible = true;
    content.onRead = () => visible = false;
    await expectLater(begin(), throwsStateError);
    expect(repository.calls, isEmpty);
    content.onRead = null;
    visible = true;
    repository.beforeReturn = () => visible = false;
    await expectLater(begin(), throwsStateError);
    expect(repository.calls, hasLength(1));
  });

  test(
    'submission delegates controlled choice and returns score-free ACK',
    () async {
      final receipt = await submit();
      expect(receipt.itemId, 'synthetic-item-b');
      expect(receipt.inserted, isTrue);
      expect(repository.calls.single, {
        'method': 'response',
        'ownerId': run.ownerId,
        'runId': run.id,
        'itemId': 'synthetic-item-b',
        'option': 'A choice',
        'responseTimeMs': 250,
        'visible': true,
      });
      repository.responseResult = AssessmentResponseResult(
        sourceEvidenceId: syntheticResponseId(run.id, 'synthetic-item-b'),
        responseCode: 'correct',
        isCorrect: true,
        inserted: false,
      );
      expect((await submit()).inserted, isFalse);
    },
  );

  test(
    'unknown item, uncontrolled choice and invalid latency never reach SQL',
    () async {
      await expectLater(submit(itemId: 'unknown'), throwsArgumentError);
      for (final option in ['', ' A choice ', 'uncontrolled', 'x' * 257]) {
        await expectLater(submit(option: option), throwsArgumentError);
      }
      for (final latency in [
        -1,
        LearningEvidenceContract.maxResponseTimeMs + 1,
      ]) {
        await expectLater(submit(latency: latency), throwsArgumentError);
      }
      expect(repository.calls, isEmpty);
    },
  );

  test(
    'catalog aliases share canonical ACK semantics but different codes cannot',
    () async {
      final definition = syntheticDefinition(aliases: true);
      run = syntheticRun(
        changes: {'formChecksumSha256': definition.formChecksumSha256},
      );
      repository = SyntheticAssessmentRepository([run], definition: definition);
      content = SyntheticContentAuthority(definition);
      useCases = AssessmentUseCases(
        repository: repository,
        instrumentCatalog: AssessmentInstrumentCatalog(entries: [definition]),
        contentAuthority: content,
      );
      repository.responseResult = AssessmentResponseResult(
        sourceEvidenceId: syntheticResponseId(run.id, 'synthetic-item-b'),
        responseCode: 'correct',
        isCorrect: true,
        inserted: false,
      );
      expect((await submit()).inserted, isFalse);
      expect((await submit(option: 'Another A choice')).inserted, isFalse);
      repository.responseResult = AssessmentResponseResult(
        sourceEvidenceId: syntheticResponseId(run.id, 'synthetic-item-b'),
        responseCode: 'incorrect',
        isCorrect: false,
        inserted: false,
      );
      await expectLater(
        submit(option: 'Another wrong choice'),
        throwsStateError,
      );
      repository.evidence[run.learningSessionId] = [syntheticEvidence(run, 0)];
      expect((await begin()).answeredItemIds, {'synthetic-item-b'});
    },
  );

  test(
    'foreign owner and completed runs cannot submit another answer',
    () async {
      repository.runs[0] = syntheticRun(changes: {'ownerId': 'foreign-owner'});
      await expectLater(submit(), throwsStateError);
      repository.runs[0] = syntheticRun(state: AssessmentRunState.completed);
      await expectLater(submit(), throwsStateError);
      expect(repository.calls, isEmpty);
    },
  );

  test(
    'response ACK cannot substitute source identity or scoring semantics',
    () async {
      for (final result in [
        const AssessmentResponseResult(
          sourceEvidenceId: 'foreign-source',
          responseCode: 'correct',
          isCorrect: true,
          inserted: true,
        ),
        AssessmentResponseResult(
          sourceEvidenceId: syntheticResponseId(run.id, 'synthetic-item-b'),
          responseCode: 'incorrect',
          isCorrect: false,
          inserted: true,
        ),
      ]) {
        repository.responseResult = result;
        await expectLater(submit(), throwsStateError);
      }
    },
  );

  test(
    'submission checks visibility after content and writer awaits',
    () async {
      content.onRead = () => visible = false;
      await expectLater(submit(), throwsStateError);
      expect(repository.calls, isEmpty);
      content.onRead = null;
      visible = true;
      repository.beforeReturn = () => visible = false;
      await expectLater(submit(), throwsStateError);
    },
  );

  test(
    'terminal actions delegate to sole writer without returning scores',
    () async {
      await useCases.completePresentation(
        ownerId: run.ownerId,
        runId: run.id,
        stillVisible: stillVisible,
      );
      await useCases.abandonPresentation(
        ownerId: run.ownerId,
        runId: run.id,
        stillVisible: stillVisible,
      );
      expect(repository.calls.map((call) => call['method']), [
        'completed',
        'abandoned',
      ]);
      expect(content.reads, 0);
      visible = false;
      await expectLater(
        useCases.completePresentation(
          ownerId: run.ownerId,
          runId: run.id,
          stillVisible: stillVisible,
        ),
        throwsStateError,
      );
      expect(repository.calls, hasLength(2));
    },
  );
}
