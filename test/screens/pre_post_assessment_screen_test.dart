import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/screens/pre_post_assessment_screen.dart';

void main() {
  testWidgets('B18 foreground owner rejection is a visible contained failure', (
    tester,
  ) async {
    final harness = await _ScreenHarness.create(canonicalOwners: true);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: PrePostAssessmentScreen(
            useCases: harness.useCases,
            command: _command,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      await harness.database.customStatement(
        'UPDATE local_owners SET is_active = 0',
      );
      await harness.database.customStatement(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) VALUES ('owner-b', 'localGuest', 1)",
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('แบบประเมินไม่พร้อมใช้งาน'), findsOneWidget);
      expect(find.text('Choose the best meaning.'), findsNothing);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        isEmpty,
      );
    } finally {
      await harness.database.customStatement(
        'UPDATE local_owners SET is_active = CASE WHEN id = ? THEN 1 ELSE 0 END',
        [_ownerId],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await harness.close();
    }
  });

  for (final afterCommit in [true, false]) {
    testWidgets('B18 terminal fault recovery afterCommit=$afterCommit', (
      tester,
    ) async {
      late _TerminalFaultRepository fault;
      final harness = await _ScreenHarness.create(
        assessmentRepository: (delegate) => fault = _TerminalFaultRepository(
          delegate,
          afterCommit: afterCommit,
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: PrePostAssessmentScreen(
              useCases: harness.useCases,
              command: _command,
            ),
          ),
        );
        await tester.pumpAndSettle();
        harness.advance(const Duration(seconds: 1));
        await tester.tap(find.text('choice-a'));
        await tester.pumpAndSettle();
        expect(fault.failed, isTrue);
        if (find.text('ลองอีกครั้ง').evaluate().isNotEmpty) {
          await tester.tap(find.text('ลองอีกครั้ง'));
          await tester.pumpAndSettle();
          if (find.text('จบแบบประเมิน').evaluate().isNotEmpty) {
            await tester.tap(find.text('จบแบบประเมิน'));
            await tester.pumpAndSettle();
          }
        }
        expect(find.text('ทำแบบประเมินเสร็จแล้ว'), findsOneWidget);
        expect(
          (await fault.getRun(_runId)).state,
          AssessmentRunState.completed,
        );
        expect(
          await harness.database.select(harness.database.answerAttempts).get(),
          hasLength(1),
        );
        final operations = await harness.database
            .select(harness.database.outboxOperations)
            .get();
        expect(
          operations.where((r) => r.operationId == 'assessmentRun:$_runId:2'),
          hasLength(1),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await harness.close();
      }
    });
  }

  testWidgets(
    'B18 response save ACK while paused excludes hidden response time',
    (tester) async {
      late _HeldResponseRepository held;
      final harness = await _ScreenHarness.create(
        definition: _twoDefinition,
        contentManifests: _ContentManifests(_twoFormBytes),
        assessmentRepository: (delegate) =>
            held = _HeldResponseRepository(delegate),
      );
      final clock = _ManualStopwatch();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: PrePostAssessmentScreen(
              useCases: harness.useCases,
              command: _command,
              responseClock: clock,
            ),
          ),
        );
        await tester.pumpAndSettle();
        clock.nowMs += 200;
        harness.advance(const Duration(milliseconds: 200));
        await tester.tap(find.text('choice-a'));
        await _pumpUntil(tester, () => held.entered.isCompleted);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        held.release.complete();
        await _pumpUntil(
          tester,
          () => find.text('Second question.').evaluate().isNotEmpty,
        );
        clock.nowMs += 60000;
        harness.advance(const Duration(milliseconds: 60000));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        clock.nowMs += 300;
        harness.advance(const Duration(milliseconds: 300));
        await tester.tap(find.text('second-a'));
        await tester.pumpAndSettle();
        expect(find.text('ทำแบบประเมินเสร็จแล้ว'), findsOneWidget);
        final rows = await harness.database
            .select(harness.database.answerAttempts)
            .get();
        expect(rows.map((r) => r.responseTimeMs).toList()..sort(), [200, 300]);
        final segments = await harness.database
            .select(harness.database.learningTimeSegments)
            .get();
        expect(
          segments.fold<int>(0, (sum, r) => sum + r.activeDurationMs),
          500,
        );
      } finally {
        if (!held.release.isCompleted) held.release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await harness.close();
      }
    },
  );

  testWidgets('pre post comparison labels percentage points and sample sizes', (
    tester,
  ) async {
    final harness = await _ScreenHarness.create();
    addTearDown(harness.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PrePostAssessmentScreen(
          useCases: harness.useCases,
          command: _command,
        ),
      ),
    );
    await tester.pumpAndSettle();
    harness.advance(const Duration(seconds: 1));
    await tester.tap(find.text('choice-a'));
    await tester.pumpAndSettle();
    expect(find.text('ทำแบบประเมินเสร็จแล้ว'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    harness.advance(const Duration(minutes: 1));
    await DriftLearningRepository(harness.database).startSession(
      LearningSessionDraft(
        id: 'session-post',
        ownerId: _ownerId,
        activityType: 'assessment',
        startedAtUtc: harness.clock.call(),
        appVersion: _appVersion,
        buildId: _buildId,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PrePostAssessmentScreen(
          useCases: harness.useCases,
          command: const AssessmentStartCommand(
            runId: 'run-post',
            learningSessionId: 'session-post',
            studyCycleId: _studyCycleId,
            phase: AssessmentPhase.post,
            instrumentId: _instrumentId,
            instrumentVersion: _instrumentVersion,
            formId: _formId,
            formVersion: _formVersion,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    harness.advance(const Duration(seconds: 1));
    await tester.tap(find.text('choice-b'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ก่อนเรียน 100% (1/1)'), findsOneWidget);
    expect(find.textContaining('หลังเรียน 0% (0/1)'), findsOneWidget);
    expect(
      find.textContaining('เปลี่ยนแปลง -100 จุดเปอร์เซ็นต์'),
      findsOneWidget,
    );
    expect(find.textContaining('-100%'), findsNothing);
  });

  test('screen source has only the score-free assessment use-case port', () {
    final source = File(
      'lib/screens/pre_post_assessment_screen.dart',
    ).readAsStringSync();

    expect(source, contains('AssessmentUseCases'));
    expect(source, isNot(contains('AssessmentInstrumentCatalog')));
    expect(source, isNot(contains('AssessmentControlledResponse')));
    expect(source, isNot(contains('recordResponse(')));
    expect(source, isNot(contains('isCorrect')));
    expect(source, isNot(contains('scoringRule')));
  });

  testWidgets(
    'runs one pinned assessment without answer feedback or background effort',
    (tester) async {
      final harness = await _ScreenHarness.create();
      addTearDown(harness.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PrePostAssessmentScreen(
            useCases: harness.useCases,
            command: _command,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('แบบประเมินก่อนเรียน'), findsOneWidget);
      expect(find.text('Choose the best meaning.'), findsOneWidget);
      expect(
        find.text('เครื่องมือ instrument-v1 · แบบประเมิน form-v1'),
        findsOneWidget,
      );
      expect(find.text('choice-a'), findsOneWidget);
      expect(find.text('choice-b'), findsOneWidget);

      harness.advance(const Duration(seconds: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      harness.advance(const Duration(hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      harness.advance(const Duration(seconds: 3));

      await tester.tap(find.text('choice-a'));
      await tester.pumpAndSettle();

      expect(find.text('ทำแบบประเมินเสร็จแล้ว'), findsOneWidget);
      expect(find.textContaining('ถูกต้อง'), findsNothing);
      expect(find.textContaining('Incorrect'), findsNothing);
      expect(find.textContaining('เฉลย'), findsNothing);
      final attempts = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      expect(attempts, hasLength(1));
      expect(attempts.single.isCorrect, isTrue);
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(
        segments.fold<int>(0, (sum, row) => sum + row.activeDurationMs),
        8000,
      );
      expect(
        segments.every(
          (row) =>
              row.activeDurationMs <=
              LearningTimeSegment.maximumActiveDuration.inMilliseconds,
        ),
        isTrue,
      );
    },
  );

  testWidgets('background during delayed start never opens hidden effort', (
    tester,
  ) async {
    _BlockingLearningTimeRepository? blockingTime;
    final harness = await _ScreenHarness.create(
      learningTimeRepository: (database, owners) =>
          blockingTime ??= _BlockingLearningTimeRepository(
            DriftLearningTimeRepository(database, owners: owners),
          ),
    );
    addTearDown(harness.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PrePostAssessmentScreen(
          useCases: harness.useCases,
          command: _command,
        ),
      ),
    );
    await blockingTime!.entered.future;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    harness.advance(const Duration(hours: 1));
    blockingTime!.release.complete();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    harness.advance(const Duration(seconds: 2));
    await tester.tap(find.text('choice-a'));
    await tester.pumpAndSettle();

    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(
      segments.fold<int>(0, (sum, row) => sum + row.activeDurationMs),
      2000,
    );
  });

  testWidgets('failure UI never retains active assessment effort', (
    tester,
  ) async {
    final harness = await _ScreenHarness.create();
    addTearDown(harness.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PrePostAssessmentScreen(
          useCases: harness.useCases,
          command: _command,
        ),
      ),
    );
    await tester.pumpAndSettle();
    harness.advance(const Duration(seconds: 5));
    await harness.database.customUpdate(
      'UPDATE research_consents SET consent_state = ?, '
      'withdrawn_at_utc_ms = ? WHERE owner_id = ?',
      variables: [
        const Variable<String>('withdrawn'),
        Variable<int>(harness.clock.value.millisecondsSinceEpoch),
        const Variable<String>(_ownerId),
      ],
    );

    await tester.tap(find.text('choice-a'));
    await tester.pumpAndSettle();
    expect(find.textContaining('แบบประเมินไม่พร้อมใช้งาน'), findsOneWidget);
    harness.advance(const Duration(hours: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(
      segments.fold<int>(0, (sum, row) => sum + row.activeDurationMs),
      5000,
    );
  });
}

final class _ScreenHarness {
  _ScreenHarness({
    required this.database,
    required this.useCases,
    required this.clock,
  });

  final AppDatabase database;
  final AssessmentUseCases useCases;
  final _Clock clock;

  static Future<_ScreenHarness> create({
    ContentManifestRepository contentManifests = const _ContentManifests(),
    AssessmentInstrumentDefinition? definition,
    bool canonicalOwners = false,
    AssessmentRepository Function(AssessmentRepository)? assessmentRepository,
    LearningTimeRepository Function(
      AppDatabase database,
      LocalOwnerRepository owners,
    )?
    learningTimeRepository,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _seed(database);
    final LocalOwnerRepository owners = canonicalOwners
        ? DriftLocalOwnerRepository(
            database,
            generateId: () => 'unused-screen-owner',
            nowUtc: () => _startedAtUtc,
          )
        : const _Owners();
    final experiments = DriftExperimentRegistry(
      DriftExperimentAssignmentRepository(database),
    );
    final consents = DriftConsentRegistry(database);
    const protocolCatalog = ResearchProtocolModeCatalog(
      mappings: [
        ResearchProtocolModeMapping(
          protocolId: _protocolId,
          experimentId: _experimentId,
          experimentVersion: 1,
          protocolVersion: _protocolVersion,
          consentVersion: 1,
          mode: EvidencePolicyRolloutMode.enforced,
        ),
      ],
    );
    final eventContexts = AssignedLearningEventContextProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
    );
    final rollout = PersistedEvidencePolicyRolloutModeProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
      currentActivityResearchStateProvider: eventContexts,
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        database,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      ),
      generateId: () => 'unused-screen-evidence',
      nowUtc: () => _startedAtUtc,
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      eventContextProvider: eventContexts,
    );
    final clock = _Clock(_startedAtUtc);
    final useCases = AssessmentUseCases(
      owners: owners,
      repository:
          assessmentRepository?.call(DriftAssessmentRepository(database)) ??
          DriftAssessmentRepository(database),
      learning: learning,
      experimentRegistry: experiments,
      consentRegistry: consents,
      rolloutModeProvider: rollout,
      protocolModeCatalog: protocolCatalog,
      instrumentCatalog: AssessmentInstrumentCatalog(
        entries: [definition ?? _definition],
      ),
      contentManifests: contentManifests,
      createActiveLearningTimeController: () => ActiveLearningTimeController(
        repository:
            learningTimeRepository?.call(database, owners) ??
            DriftLearningTimeRepository(database, owners: owners),
        monotonicMicros: () => clock.monotonicMicros,
        nowUtc: clock.call,
        timezoneContext: (_) => const LearningTimeZoneContext(
          timezoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
        scheduleIdle: (_, _) => () {},
      ),
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      nowUtc: clock.call,
    );
    return _ScreenHarness(database: database, useCases: useCases, clock: clock);
  }

  void advance(Duration duration) => clock.advance(duration);

  Future<void> close() => database.close();
}

final class _BlockingLearningTimeRepository implements LearningTimeRepository {
  _BlockingLearningTimeRepository(this._delegate);

  final LearningTimeRepository _delegate;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> append(LearningTimeSegment segment) => _delegate.append(segment);

  @override
  Future<Duration> activeDuration(String sessionId) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return _delegate.activeDuration(sessionId);
  }
}

final class _Clock {
  _Clock(this.value);

  DateTime value;
  int monotonicMicros = 0;

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
    monotonicMicros += duration.inMicroseconds;
  }
}

final class _ContentManifests implements ContentManifestRepository {
  const _ContentManifests([this.formBytes]);
  final List<int>? formBytes;

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async => VerifiedContentManifest(
    manifest: ContentManifest(
      storageId: 'manifest-form-a-r1',
      identity: identity,
      checksumSha256: sha256.convert((formBytes ?? _formBytes)).toString(),
      byteLength: (formBytes ?? _formBytes).length,
      provenance: ContentProvenance.packaged,
      sourceUri: 'asset://assessment/form-a',
      reviewState: ContentReviewState.approved,
      publicationState: ContentPublicationState.published,
      createdAtUtc: _consentAtUtc,
      reviewedAtUtc: _consentAtUtc,
      publishedAtUtc: _consentAtUtc,
    ),
    bytes: Uint8List.fromList((formBytes ?? _formBytes)),
  );
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: _ownerId, createdAtUtc: _consentAtUtc);

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => identity.LocalOwner(
    id: _ownerId,
    firebaseUid: firebaseUid,
    createdAtUtc: _consentAtUtc,
  );
}

Future<void> _seed(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      const Variable<String>(_ownerId),
      const Variable<String>('localGuest'),
      Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('consent-assessment-screen'),
      const Variable<String>(_ownerId),
      const Variable<int>(1),
      const Variable<String>('accepted'),
      Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments('
    'id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      Variable<String>(
        DriftExperimentAssignmentRepository.canonicalAssignmentId(
          ownerId: _ownerId,
          experimentId: _experimentId,
          experimentVersion: 1,
        ),
      ),
      const Variable<String>(_ownerId),
      const Variable<String>(_experimentId),
      const Variable<int>(1),
      const Variable<String>('enforced'),
      const Variable<String>(_protocolVersion),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: _categoryId,
          ownerId: _ownerId,
          name: 'Assessment',
          normalizedName: 'assessment',
          createdAtUtcMs: _consentAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: _consentAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: _wordId,
          ownerId: _ownerId,
          categoryId: _categoryId,
          spelling: 'evaluate',
          normalizedSpelling: 'evaluate',
          meaning: 'assess',
          normalizedMeaning: 'assess',
          partOfSpeech: 'verb',
          createdAtUtcMs: _consentAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: _consentAtUtc.millisecondsSinceEpoch,
        ),
      );
  await DriftLearningRepository(database).startSession(
    LearningSessionDraft(
      id: _sessionId,
      ownerId: _ownerId,
      activityType: 'assessment',
      startedAtUtc: _sessionStartedAtUtc,
      appVersion: _appVersion,
      buildId: _buildId,
    ),
  );
}

final _definition = AssessmentInstrumentDefinition(
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
  formContentRevision: 1,
  sourceState: AssessmentCatalogSourceState.approved,
  reviewState: AssessmentCatalogReviewState.approved,
  protocolId: _protocolId,
  experimentId: _experimentId,
  experimentVersion: 1,
  contentRevision: 'assessment-content-v1',
  instrumentBytes: _instrumentBytes,
  formBytes: _formBytes,
  instrumentChecksumSha256: sha256.convert(_instrumentBytes).toString(),
  formChecksumSha256: sha256.convert(_formBytes).toString(),
  items: const [
    AssessmentItemDefinition(
      itemId: _itemId,
      prompt: 'Choose the best meaning.',
      wordId: _wordId,
      promptMode: 'assessmentResponse',
      scoringRuleVersion: 'score-v1',
      responses: {
        'choice-a': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'choice-b': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
    ),
  ],
);

const _command = AssessmentStartCommand(
  runId: _runId,
  learningSessionId: _sessionId,
  studyCycleId: _studyCycleId,
  phase: AssessmentPhase.pre,
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
);

const _ownerId = 'owner-assessment-screen';
const _categoryId = 'category-assessment-screen';
const _wordId = 'word-assessment-screen';
const _sessionId = 'session-assessment-screen';
const _runId = 'run-assessment-screen';
const _studyCycleId = 'study-cycle-screen';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1.0.0';
const _experimentId = 'assessment-experiment';
const _instrumentId = 'instrument-core';
const _instrumentVersion = 'instrument-v1';
const _formId = 'form-a';
const _formVersion = 'form-v1';
const _itemId = 'item-meaning-1';
const _appVersion = '1.0.0';
const _buildId = 'f28-screen-test';
const _instrumentBytes = <int>[1, 2, 3];
final _formBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
  formContentRevision: 1,
  items: const [
    AssessmentItemDefinition(
      itemId: _itemId,
      prompt: 'Choose the best meaning.',
      wordId: _wordId,
      promptMode: 'assessmentResponse',
      scoringRuleVersion: 'score-v1',
      responses: {
        'choice-a': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'choice-b': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
    ),
  ],
);
final _consentAtUtc = DateTime.utc(2026, 8, 1, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 2, 8);
final _sessionStartedAtUtc = DateTime.utc(2026, 8, 14, 9, 59);
final _startedAtUtc = DateTime.utc(2026, 8, 14, 10);

class _DelegatingAssessmentRepository implements AssessmentRepository {
  _DelegatingAssessmentRepository(this.delegate);

  final AssessmentRepository delegate;

  @override
  Future<AssessmentRun> start(AssessmentRun run) => delegate.start(run);

  @override
  Future<AssessmentRun> getRun(String runId) => delegate.getRun(runId);

  @override
  Future<AssessmentRun> complete({
    required String runId,
    required DateTime completedAtUtc,
    AssessmentCompletionAuthorityGuard? authorityGuard,
  }) => delegate.complete(
    runId: runId,
    completedAtUtc: completedAtUtc,
    authorityGuard: authorityGuard,
  );

  @override
  Future<AssessmentRun> abandon({
    required String runId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandon(runId: runId, abandonedAtUtc: abandonedAtUtc);

  @override
  Future<AssessmentRun> requireActiveForResponse({
    required String runId,
    required DateTime occurredAtUtc,
  }) => delegate.requireActiveForResponse(
    runId: runId,
    occurredAtUtc: occurredAtUtc,
  );

  @override
  Future<T> serializeActiveResponse<T>({
    required String runId,
    required DateTime occurredAtUtc,
    required AssessmentActiveResponseWork<T> work,
  }) => delegate.serializeActiveResponse(
    runId: runId,
    occurredAtUtc: occurredAtUtc,
    work: work,
  );

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) => delegate.listRunsForStudyCycle(
    ownerId: ownerId,
    studyCycleId: studyCycleId,
  );

  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) => delegate.listOutcomeEvidence(
    ownerId: ownerId,
    learningSessionId: learningSessionId,
  );
}

final class _ManualStopwatch implements Stopwatch {
  int nowMs = 0;
  int _elapsed = 0;
  int? _started;
  @override
  bool get isRunning => _started != null;
  @override
  int get elapsedMilliseconds =>
      _elapsed + (_started == null ? 0 : nowMs - _started!);
  @override
  void start() {
    _started ??= nowMs;
  }

  @override
  void stop() {
    _elapsed = elapsedMilliseconds;
    _started = null;
  }

  @override
  void reset() {
    _elapsed = 0;
    if (isRunning) _started = nowMs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _HeldResponseRepository extends _DelegatingAssessmentRepository {
  _HeldResponseRepository(super.delegate);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<T> serializeActiveResponse<T>({
    required String runId,
    required DateTime occurredAtUtc,
    required AssessmentActiveResponseWork<T> work,
  }) async {
    final result = await super.serializeActiveResponse(
      runId: runId,
      occurredAtUtc: occurredAtUtc,
      work: work,
    );
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return result;
  }
}

final _twoItems = [
  ..._definition.items,
  const AssessmentItemDefinition(
    itemId: 'item-second',
    prompt: 'Second question.',
    wordId: _wordId,
    promptMode: 'assessmentResponse',
    scoringRuleVersion: 'score-v1',
    responses: {
      'second-a': AssessmentControlledResponse(
        responseCode: 'correct',
        isCorrect: true,
      ),
      'second-b': AssessmentControlledResponse(
        responseCode: 'incorrect',
        isCorrect: false,
      ),
    },
  ),
];
final _twoFormBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
  formContentRevision: 1,
  items: _twoItems,
);
final _twoDefinition = AssessmentInstrumentDefinition(
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
  formContentRevision: 1,
  sourceState: AssessmentCatalogSourceState.approved,
  reviewState: AssessmentCatalogReviewState.approved,
  protocolId: _protocolId,
  experimentId: _experimentId,
  experimentVersion: 1,
  contentRevision: 'assessment-content-v1',
  instrumentBytes: _instrumentBytes,
  formBytes: _twoFormBytes,
  instrumentChecksumSha256: sha256.convert(_instrumentBytes).toString(),
  formChecksumSha256: sha256.convert(_twoFormBytes).toString(),
  items: _twoItems,
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'bounded asynchronous fixture progress');
}

final class _TerminalFaultRepository extends _DelegatingAssessmentRepository {
  _TerminalFaultRepository(super.delegate, {required this.afterCommit});
  final bool afterCommit;
  bool failed = false;
  @override
  Future<AssessmentRun> complete({
    required String runId,
    required DateTime completedAtUtc,
    AssessmentCompletionAuthorityGuard? authorityGuard,
  }) async {
    if (!failed && !afterCommit) {
      failed = true;
      throw StateError('injected failure before terminal commit');
    }
    final result = await super.complete(
      runId: runId,
      completedAtUtc: completedAtUtc,
      authorityGuard: authorityGuard,
    );
    if (!failed) {
      failed = true;
      throw StateError(
        'injected lost terminal acknowledgement after durable commit',
      );
    }
    return result;
  }
}
