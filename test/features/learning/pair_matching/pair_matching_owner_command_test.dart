import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';

import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'pair_matching_owner_upgrade_test.dart' show mergePairOwner, planTap;
import 'pair_timeout_recovery_test.dart' show timedPlan, clocked, decision;

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'real merged runtime rejects R commands while P tile captures R evidence',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await mergePairOwner(h);
      final c = await h.restore();
      addTearDown(c.dispose);
      expect(h.owner, isNot(c.state.plan.ownerId));
      final prompt = _tile(c, 'synthetic-0', PairTileSide.prompt);
      await _rejectUnchanged(
        h.db,
        c,
        () => h.nextId,
        _tileCopy(prompt, owner: h.owner),
      );
      await c.dispatch(prompt);
      final answer = _tile(c, 'synthetic-0', PairTileSide.target);
      await _rejectUnchanged(
        h.db,
        c,
        () => h.nextId,
        _tileCopy(answer, owner: h.owner),
      );
      await c.dispatch(answer);
      final row = (await h.db.select(h.db.answerAttempts).get()).single;
      final event = await h.real.events.readBySourceEvidenceId(row.id);
      expect(row.ownerId, h.owner);
      expect(event!.ownerIdentity, h.owner);
      expect(event.actorIdentity, h.owner);
      expect(c.state.attempts.single.fingerprint, answer.fingerprint);
      expect(answer.ownerId, h.operation.plan.ownerId);
      expect(h.nextId, 1);
    },
  );

  test(
    'old P answer duplicate survives real merge and disk reopen without changing hashes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pm8-command-reopen-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      final h = PairHarness(executor: NativeDatabase(file));
      await h.initialize();
      final before = await h.restore();
      await planTap(h, before, 'synthetic-0', PairTileSide.prompt);
      final command = _tile(before, 'synthetic-0', PairTileSide.target);
      await before.dispatch(command);
      final oldAttempt = before.state.attempts.single;
      final oldAttemptBytes = jsonEncode(oldAttempt.toJson());
      final startBytes = h.operation.stableSerialization;
      final planBytes = h.operation.plan.stableSerialization;
      await mergePairOwner(h);
      before.dispose();
      await h.db.close();

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await file.delete();
        await directory.delete();
      });
      final repository = DriftLearningRepository(database);
      var captures = 0;
      final learning = LearningUseCases(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => throw StateError('must not mint a new owner'),
          nowUtc: h.learning.nowUtc,
        ),
        repository: repository,
        generateId: () => 'pm8-post-reopen-${++captures}',
        nowUtc: h.learning.nowUtc,
        buildInfo: h.learning.buildInfo,
      );
      final c = await PairMatchingSessionCoordinator.restore(
        operation: h.operation,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        activeOwnerId: () => h.owner,
        monotonicMicros: () => 0,
      );
      addTearDown(c.dispose);
      expect(c.operation.stableSerialization, startBytes);
      expect(c.state.plan.stableSerialization, planBytes);
      expect(jsonEncode(c.state.attempts.single.toJson()), oldAttemptBytes);
      expect(
        c.state.attempts.single.resolutionFingerprint,
        oldAttempt.resolutionFingerprint,
      );
      final unchanged = await _snapshot(database, c, captures);
      expect(
        identical(PairMatchingEngine.reduce(c.state, command).state, c.state),
        true,
      );
      await c.dispatch(command);
      expect(await _snapshot(database, c, captures), unchanged);
      for (final altered in [
        _tileCopy(command, word: 'synthetic-1'),
        _tileCopy(command, responseTimeMs: 26),
        _tileCopy(command, owner: h.owner),
      ]) {
        expect(altered.fingerprint, isNot(command.fingerprint));
        await _rejectUnchanged(database, c, () => captures, altered);
      }
      final oldRow =
          (await database.select(database.answerAttempts).get()).single;
      expect(oldRow.ownerId, h.owner);
      final oldEvent = await repository.events.readBySourceEvidenceId(
        oldRow.id,
      );
      expect(oldEvent!.actorIdentity, command.ownerId);
      expect(captures, 0);
      // The unchanged duplicate controls must not accidentally retire live R.
      await c.dispatch(_tile(c, 'synthetic-1', PairTileSide.prompt));
      await c.dispatch(_tile(c, 'synthetic-1', PairTileSide.target));
      expect(captures, 1);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  test(
    'post-merge P reveal and guided commands preserve support and reject changed duplicates',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await mergePairOwner(h);
      final c = await h.restore();
      addTearDown(c.dispose);
      PairRevealMapping reveal({String? owner, String word = 'synthetic-0'}) =>
          PairRevealMapping(
            operationId: '0:pm8-reveal',
            ownerId: owner ?? h.operation.plan.ownerId,
            sessionId: h.operation.plan.learningSessionId,
            roundOrdinal: 0,
            expectedRevision: 0,
            wordId: word,
          );
      await _rejectUnchanged(h.db, c, () => h.nextId, reveal(owner: h.owner));
      final acceptedReveal = reveal();
      await c.dispatch(acceptedReveal);
      expect(c.state.supportAtRevision['synthetic-0'], 0);
      final revealed = await _snapshot(h.db, c, h.nextId);
      await c.dispatch(acceptedReveal);
      expect(await _snapshot(h.db, c, h.nextId), revealed);
      await _rejectUnchanged(
        h.db,
        c,
        () => h.nextId,
        reveal(word: 'synthetic-1'),
      );
      expect(h.nextId, 0);

      // A prior explicit reveal supplies the actual support prerequisite; this
      // is a learner-confirmed guided answer, never a fabricated repair ticket.
      PairConfirmGuidedMapping confirm({String? owner, int responseMs = 25}) =>
          PairConfirmGuidedMapping(
            operationId: '1:pm8-guided',
            ownerId: owner ?? h.operation.plan.ownerId,
            sessionId: h.operation.plan.learningSessionId,
            roundOrdinal: 0,
            expectedRevision: 1,
            wordId: 'synthetic-0',
            shownSupportRevision: 0,
            responseTimeMs: responseMs,
          );
      await _rejectUnchanged(h.db, c, () => h.nextId, confirm(owner: h.owner));
      final acceptedConfirmation = confirm();
      await c.dispatch(acceptedConfirmation);
      expect(c.state.attempts.single.role, PairAttemptRole.guidedCompletion);
      expect(
        c.state.attempts.single.fingerprint,
        acceptedConfirmation.fingerprint,
      );
      final row = (await h.db.select(h.db.answerAttempts).get()).single;
      expect(row.ownerId, h.owner);
      expect(row.evidenceClass, 'guidedPractice');
      expect(
        (await h.real.events.readBySourceEvidenceId(row.id))!.actorIdentity,
        h.owner,
      );
      final guided = await _snapshot(h.db, c, h.nextId);
      await c.dispatch(acceptedConfirmation);
      expect(await _snapshot(h.db, c, h.nextId), guided);
      await _rejectUnchanged(h.db, c, () => h.nextId, confirm(responseMs: 26));
      await _rejectUnchanged(h.db, c, () => h.nextId, confirm(owner: h.owner));
      expect(h.nextId, 1);
    },
  );

  for (final measured in [false, true]) {
    test(
      'real merged timed session keeps P decisions and rejects R or changed action measured=$measured',
      () async {
        var micros = 0;
        final h = PairHarness(pinnedPlan: timedPlan());
        addTearDown(h.db.close);
        await h.initialize(measured: measured);
        var c = await clocked(h, () => micros);
        c.resumeInteraction();
        micros = 60000000;
        final oldExpiry = decision(c, PairTimerAction.expire);
        await c.dispatch(oldExpiry);
        final startBytes = c.operation.stableSerialization;
        final planBytes = c.state.plan.stableSerialization;
        final oldFingerprint = c.timer.lastFingerprint;
        await mergePairOwner(h);
        c.dispose();
        c = await clocked(h, () => micros);
        expect(c.timer.mode, PairTimerMode.timeoutDecision);
        expect(c.timer.lastFingerprint, oldFingerprint);
        final beforeRetry = await _snapshot(h.db, c, h.nextId);
        await c.dispatch(oldExpiry);
        expect(await _snapshot(h.db, c, h.nextId), beforeRetry);
        await _timerNegativeControls(h, c, oldExpiry);

        Future<void> accept(PairTimerAction action) async {
          final command = decision(c, action);
          expect(command.ownerId, h.operation.plan.ownerId);
          await _rejectUnchanged(
            h.db,
            c,
            () => h.nextId,
            _timerCopy(command, owner: h.owner),
          );
          await c.dispatch(command);
          expect(c.timer.lastFingerprint, command.fingerprint);
          final accepted = await _snapshot(h.db, c, h.nextId);
          await c.dispatch(command);
          expect(await _snapshot(h.db, c, h.nextId), accepted);
          await _timerNegativeControls(h, c, command);
        }

        await accept(PairTimerAction.extend);
        expect(c.timer.extensionUsed, true);
        expect(c.timer.remainingActiveMs, 30000);
        c.resumeInteraction();
        micros += 30000000;
        await accept(PairTimerAction.expire);
        await accept(PairTimerAction.restart);
        expect(c.state.roundOrdinal, 1);
        expect(c.timer.extensionUsed, true);
        c.resumeInteraction();
        micros += 60000000;
        await accept(PairTimerAction.expire);
        await accept(PairTimerAction.continueUntimed);
        expect(c.timer.mode, PairTimerMode.continuedUntimed);
        expect(c.timer.interactiveElapsedMs, measured ? 150000 : null);
        expect(c.state.plan.stableSerialization, planBytes);
        expect(c.operation.stableSerialization, startBytes);
        expect(c.state.attempts, isEmpty);
        expect(h.nextId, 0);
        expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
        final finalTimer = jsonEncode(c.timer.toJson()..remove('reasons'));
        final finalState = jsonEncode(c.state.toJson());
        c.dispose();
        c = await clocked(h, () => micros);
        expect(jsonEncode(c.state.toJson()), finalState);
        expect(jsonEncode(c.timer.toJson()..remove('reasons')), finalTimer);
        expect(
          c.timerPaused,
          true,
          reason: 'a new clock requires a fresh interaction lease',
        );
        c.dispose();
      },
    );
  }
}

PairSelectTile _tile(
  PairMatchingSessionCoordinator c,
  String word,
  PairTileSide side,
) => PairSelectTile(
  operationId: '${c.state.operationRevision}:pm8-tile',
  ownerId: c.operation.plan.ownerId,
  sessionId: c.operation.plan.learningSessionId,
  roundOrdinal: c.state.roundOrdinal,
  expectedRevision: c.state.operationRevision,
  tile: PairTile(side, word),
  responseTimeMs: 25,
);

PairSelectTile _tileCopy(
  PairSelectTile command, {
  String? owner,
  String? word,
  int? responseTimeMs,
}) => PairSelectTile(
  operationId: command.operationId,
  ownerId: owner ?? command.ownerId,
  sessionId: command.sessionId,
  roundOrdinal: command.roundOrdinal,
  expectedRevision: command.expectedRevision,
  tile: PairTile(command.tile.side, word ?? command.tile.wordId),
  responseTimeMs: responseTimeMs ?? command.responseTimeMs,
);

PairTimerDecision _timerCopy(
  PairTimerDecision command, {
  String? owner,
  PairTimerAction? action,
}) => PairTimerDecision(
  operationId: command.operationId,
  ownerId: owner ?? command.ownerId,
  sessionId: command.sessionId,
  roundOrdinal: command.roundOrdinal,
  expectedRevision: command.expectedRevision,
  action: action ?? command.action,
);

Future<void> _timerNegativeControls(
  PairHarness h,
  PairMatchingSessionCoordinator c,
  PairTimerDecision accepted,
) async {
  await _rejectUnchanged(
    h.db,
    c,
    () => h.nextId,
    _timerCopy(accepted, owner: h.owner),
  );
  final changed = _timerCopy(
    accepted,
    action: accepted.action == PairTimerAction.extend
        ? PairTimerAction.continueUntimed
        : PairTimerAction.extend,
  );
  expect(changed.fingerprint, isNot(accepted.fingerprint));
  await _rejectUnchanged(h.db, c, () => h.nextId, changed);
}

Future<void> _rejectUnchanged(
  AppDatabase database,
  PairMatchingSessionCoordinator c,
  int Function() captures,
  PairMatchingCommand command,
) async {
  final before = await _snapshot(database, c, captures());
  expect(() => PairMatchingEngine.reduce(c.state, command), throwsStateError);
  await expectLater(c.dispatch(command), throwsStateError);
  expect(await _snapshot(database, c, captures()), before);
}

Future<String> _snapshot(
  AppDatabase database,
  PairMatchingSessionCoordinator c,
  int captures,
) async => jsonEncode({
  'engine': c.state.toJson(),
  'timer': c.timer.toJson(),
  'captures': captures,
  for (final table in [
    'learning_sessions',
    'answer_attempts',
    'events_v2',
    'outbox_operations',
  ])
    table: [
      for (final row
          in await database
              .customSelect('SELECT * FROM $table ORDER BY 1')
              .get())
        row.data,
    ],
});
