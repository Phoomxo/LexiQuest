import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/presentation/native_exercise_resume_screen.dart';
import 'package:vocab_learning_app/features/learning/presentation/lesson_scaffold.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/configured_quiz_harness.dart';
import '../support/motivation_presentation_io.dart'
    show motivationPresentationIo;
import '../support/sentence_scramble_native_harness.dart'
    show SyntheticSentenceScrambleProvider;

void main() {
  for (final mode in [
    'dictation',
    'wordScramble',
    'sentenceScramble',
    'clozeTyped',
    'clozeChoice',
  ]) {
    for (final path in [
      'direct',
      'through History',
      'through Today',
      'answered Today',
      'pending History',
      'answered History',
      'closing History',
      'completed History',
      if (mode == 'dictation') 'assistance ACK',
      if (mode == 'wordScramble') ...[
        'owner before read',
        'owner during read',
        'hook retry',
      ],
    ]) {
      final throughHistory = path.contains('History');
      final throughToday = path.contains('Today');
      final completed = path == 'completed History';
      final pending = path == 'pending History';
      final answered = path == 'answered History' || path == 'answered Today';
      final closing = path == 'closing History';
      final submitted = pending || answered || closing || completed;
      final ownerBefore = path == 'owner before read';
      final ownerDuring = path == 'owner during read';
      final ownerNegative = ownerBefore || ownerDuring;
      testWidgets(
        'cold restart $path restores acknowledged $mode input without starting another session',
        (tester) async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          final directory = (await tester.runAsync(
            () =>
                Directory.systemTemp.createTemp('lexiquest-native-ui-resume-'),
          ))!;
          late ConfiguredQuizHarness storage;
          late LearningUseCases learning;
          var nextId = 0;
          var hookCalls = 0;
          final owners = StreamController<String?>.broadcast(sync: true);
          final voice = _Voice();
          final blockedProvider = _NoRegeneration();
          _ResumeRepository? repository;
          var opened = false;
          try {
            storage = (await tester.runAsync(
              () => ConfiguredQuizHarness.open(
                file: File('${directory.path}/native.sqlite'),
              ),
            ))!;
            opened = true;
            LearningUseCases create({
              bool generation = false,
              _ResumeRepository? wrapped,
            }) => LearningUseCases(
              owners: storage.owners,
              repository:
                  wrapped ??
                  DriftLearningRepository(
                    storage.database,
                    ownerWrites: storage.ownerWrites,
                  ),
              generateId: () => 'synthetic-resume-ui-${++nextId}',
              nowUtc: () => storage.now,
              buildInfo: const AppBuildInfo(
                version: '1.0.0+1',
                buildId: 'synthetic-native-ui',
              ),
              contentProvider: generation
                  ? SyntheticSentenceScrambleProvider(storage.database)
                  : blockedProvider,
              beforeOrdinaryAnswer: path == 'hook retry'
                  ? ({
                      required String expectedOwnerId,
                      required String sessionId,
                      required bool Function() stillCurrent,
                    }) async {
                      hookCalls++;
                      expect(expectedOwnerId, configuredOwnerId);
                      expect(stillCurrent(), isTrue);
                      if (hookCalls == 1) {
                        throw StateError(
                          'Synthetic ordinary preparation failure',
                        );
                      }
                    }
                  : null,
            );
            learning = create(generation: true);
            final state = (await tester.runAsync(() async {
              final prepared = switch (mode) {
                'dictation' => await learning.prepareDictation(
                  categoryId: configuredCategoryId,
                  stillCurrent: () => true,
                ),
                'wordScramble' => await learning.prepareWordScramble(
                  categoryId: configuredCategoryId,
                  stillCurrent: () => true,
                ),
                'sentenceScramble' => await learning.prepareSentenceScramble(
                  categoryId: configuredCategoryId,
                  stillCurrent: () => true,
                ),
                _ => await learning.prepareCloze(
                  categoryId: configuredCategoryId,
                  variant: mode == 'clozeTyped'
                      ? ClozeVariant.typed
                      : ClozeVariant.choice,
                  stillCurrent: () => true,
                ),
              };
              final exercise = await learning.startNativeExercise(
                prepared!,
                stillCurrent: () => true,
              );
              final initial = await learning.readNativeExerciseState(
                exercise,
                stillCurrent: () => true,
              );
              final draft = path == 'hook retry'
                  ? NativeExerciseDraft(
                      text: 'synthetic older draft',
                      responseTimeMs: 321,
                    )
                  : path == 'assistance ACK'
                  ? NativeExerciseDraft(
                      text: 'synthetic unassisted draft',
                      responseTimeMs: 321,
                    )
                  : _draft(exercise);
              final drafted = await learning.saveNativeDraft(
                state: initial,
                draft: draft,
                stillCurrent: () => true,
              );
              if (submitted) {
                final pendingState = await learning.stageNativeAnswer(
                  state: drafted,
                  input: _correctInput(exercise),
                  stillCurrent: () => true,
                );
                if (!pending) {
                  await learning.commitNativeAnswer(
                    exercise,
                    pendingState.checkpoint.answer!,
                    stillCurrent: () => true,
                  );
                  final answered = await learning.readNativeExerciseState(
                    exercise,
                    stillCurrent: () => true,
                  );
                  if (closing || completed) {
                    final closingState = await learning.stageNativeFinish(
                      state: answered,
                      stillCurrent: () => true,
                    );
                    if (completed) {
                      await learning.finishNativeExercise(
                        NativeFinishIntent(
                          exercise: exercise,
                          answer: closingState.checkpoint.answer!,
                          endedAtUtc: closingState.checkpoint.endedAtUtc!,
                        ),
                        stillCurrent: () => true,
                      );
                    }
                  }
                }
              }
              storage = await storage.reopen();
              storage.now = storage.now.add(const Duration(hours: 17));
              repository = _ResumeRepository(
                DriftLearningRepository(
                  storage.database,
                  ownerWrites: storage.ownerWrites,
                ),
              );
              learning = create(wrapped: repository);
              return learning.resumeNativeExercise(
                sessionId: exercise.id,
                expectedOwnerId: configuredOwnerId,
                stillCurrent: () => true,
              );
            }))!;
            if (ownerBefore) {
              await tester.runAsync(
                () => storage.switchOwner(configuredOtherOwnerId),
              );
            }
            var before = (await tester.runAsync(storage.snapshot))!;
            repository!.completedResumes = 0;
            if (ownerDuring) repository!.resumeAckGate = Completer<void>();
            final ownerStream = owners.stream;
            final screen = switch (state.exercise) {
              DictationSession exercise => DictationQuizScreen(
                session: exercise,
                learning: learning,
                resumeState: state,
                ownerChanges: ownerStream,
                voice: VoiceUseCases(voice),
                languageCode: 'en',
              ),
              WordScrambleSession exercise => WordScrambleScreen(
                session: exercise,
                learning: learning,
                resumeState: state,
                ownerChanges: ownerStream,
                languageCode: 'en',
              ),
              SentenceScrambleSession exercise => SentenceScrambleScreen(
                session: exercise,
                learning: learning,
                resumeState: state,
                ownerChanges: ownerStream,
                voice: VoiceUseCases(voice),
                languageCode: 'en',
              ),
              ClozeSession exercise => FillInTheBlanksScreen(
                session: exercise,
                learning: learning,
                resumeState: state,
                ownerChanges: ownerStream,
                languageCode: 'en',
              ),
            };
            await tester.pumpWidget(
              AppDependenciesScope(
                dependencies: AppDependencies(
                  runtimeStatus: const AppRuntimeStatus(
                    localData: RuntimeAvailability.ready,
                    firebase: RuntimeAvailability.unavailable,
                    supabase: RuntimeAvailability.unavailable,
                    backends: RuntimeAvailability.unavailable,
                  ),
                  config: null,
                  guestSessionService: _Guest(),
                  learning: learning,
                  voice: VoiceUseCases(voice),
                  progress: ProgressUseCases(
                    owners: storage.owners,
                    queries: DriftProgressQueries(storage.database),
                    nowUtc: () => storage.now,
                  ),
                ),
                child: MaterialApp(
                  home: throughHistory
                      ? LearningHistoryScreen(
                          languageCode: 'en',
                          ownerChanges: ownerStream,
                          loader: ({before}) =>
                              DriftLearningHistoryQueries(
                                storage.database,
                              ).load(
                                ownerId: configuredOwnerId,
                                nowUtc: storage.now,
                                before: before,
                              ),
                        )
                      : throughToday
                      ? const ChooseModeScreen()
                      : ownerNegative
                      ? NativeExerciseResumeScreen(
                          sessionId: state.exercise.id,
                          expectedOwnerId: configuredOwnerId,
                          learning: learning,
                          stillCurrent: () => true,
                          ownerChanges: ownerStream,
                          languageCode: 'en',
                        )
                      : screen,
                ),
              ),
            );
            owners.add(
              ownerBefore ? configuredOtherOwnerId : configuredOwnerId,
            );
            if (ownerNegative) {
              if (ownerDuring) {
                await _until(tester, () => repository!.completedResumes == 1);
                await tester.runAsync(
                  () => storage.switchOwner(configuredOtherOwnerId),
                );
                owners.add(configuredOtherOwnerId);
                before = (await tester.runAsync(storage.snapshot))!;
                repository!.resumeAckGate!.complete();
              }
              await _until(
                tester,
                () => find
                    .byKey(const ValueKey('native-resume-unavailable'))
                    .evaluate()
                    .isNotEmpty,
              );
              expect(find.byType(WordScrambleScreen), findsNothing);
              expect(repository!.starts, 0);
              expect(blockedProvider.requests, 0);
              expect(voice.spoken, 0);
              await tester.runAsync(repository!.settle);
              expect((await tester.runAsync(storage.snapshot))!, before);
              expect(tester.takeException(), isNull);
              return;
            }
            if (throughHistory) {
              final action = completed ? 'ดูผล' : 'เล่นต่อ';
              await _until(
                tester,
                () => find.text(action).evaluate().isNotEmpty,
              );
              await tester.ensureVisible(find.text(action));
              await _until(
                tester,
                () => find.text(action).hitTestable().evaluate().isNotEmpty,
              );
              expect(find.text(action).hitTestable(), findsOneWidget);
              await tester.tap(find.text(action).hitTestable());
              await tester.pump();
            }
            if (throughToday) {
              final action = find.byKey(const ValueKey('today-resume-start'));
              await _until(tester, () => action.evaluate().isNotEmpty);
              await tester.ensureVisible(action);
              await tester.pump();
              await tester.tap(action.hitTestable());
              await tester.pump();
            }
            await _until(
              tester,
              () =>
                  repository!.completedResumes >=
                      ((throughHistory || throughToday) && !completed
                          ? 2
                          : 1) ||
                  repository!.completedStarts > 0,
            );
            await tester.pump(const Duration(milliseconds: 16));
            await tester.pump(const Duration(milliseconds: 350));
            expect(
              repository!.starts,
              0,
              reason:
                  'a resumed screen must read the issued checkpoint instead of starting again',
            );
            expect(blockedProvider.requests, 0);
            if (completed) {
              expect(find.byType(ScoreScreen), findsOneWidget);
              final score = tester.widget<ScoreScreen>(
                find.byType(ScoreScreen),
              );
              expect(
                score.correctAnswers,
                state.completedSummary!.correctCount,
              );
              expect(score.wrongAnswers, state.completedSummary!.wrongCount);
              expect(score.score, state.completedSummary!.score);
              expect(find.byType(WordScrambleScreen), findsNothing);
              expect(voice.spoken, 0);
              expect((await tester.runAsync(storage.snapshot))!, before);
              expect(tester.takeException(), isNull);
              return;
            }
            final draft = state.checkpoint.draft;
            expect(find.byType(LessonScaffold), findsOneWidget);
            final progress = tester.widget<LessonProgress>(
              find.byType(LessonProgress),
            );
            expect(progress.current, 1);
            expect(progress.total, 1);
            if (state.exercise is ChoiceClozeSession) {
              expect(
                tester
                    .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                    .groupValue,
                draft.optionId,
              );
            } else if (draft.tileSlots != null) {
              final word = state.exercise is WordScrambleSession;
              final bank = word
                  ? (state.exercise as WordScrambleSession).letters
                  : (state.exercise as SentenceScrambleSession).tokenOrder
                        .map(
                          (index) => (state.exercise as SentenceScrambleSession)
                              .content
                              .tokens[index],
                        )
                        .toList();
              for (var index = 0; index < draft.tileSlots!.length; index++) {
                final slot = find.byKey(
                  ValueKey('${word ? 'scramble' : 'sentence'}-slot-$index'),
                );
                final text = tester
                    .widget<Text>(
                      find
                          .descendant(of: slot, matching: find.byType(Text))
                          .last,
                    )
                    .data;
                expect(
                  text?.trim(),
                  draft.tileSlots![index] == null
                      ? ''
                      : bank[draft.tileSlots![index]!],
                );
              }
            } else {
              final key = '${_prefix(mode)}-response';
              await _scrollTo(tester, mode, find.byKey(ValueKey(key)));
              expect(
                tester
                    .widget<TextField>(find.byKey(ValueKey(key)))
                    .controller!
                    .text,
                draft.text,
              );
            }
            expect(
              voice.spoken,
              0,
              reason: 'a restored screen needs an explicit audio request',
            );
            if (!submitted) {
              await _scrollTo(
                tester,
                mode,
                find.byKey(const ValueKey('native-draft-status')),
              );
              expect(
                find.text(
                  throughToday
                      ? 'ฉบับร่างบันทึกแล้ว ยังไม่เป็นคำตอบที่ส่ง'
                      : 'Draft saved. Answer not recorded.',
                ),
                findsOneWidget,
              );
            }
            expect((await tester.runAsync(storage.snapshot))!, before);
            if (path == 'hook retry') {
              const submittedText = 'synthetic submitted response';
              final response = find.byKey(const ValueKey('scramble-response'));
              await _scrollTo(tester, mode, response);
              await tester.enterText(response, submittedText);
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              final save = find.byKey(const ValueKey('scramble-save'));
              await _scrollTo(tester, mode, save);
              final originalIdCount = nextId;
              await tester.tap(save);
              final retry = find.byKey(const ValueKey('scramble-retry'));
              await _until(tester, () => hookCalls == 1);
              await tester.pumpAndSettle();
              await _scrollTo(tester, mode, retry);
              expect(hookCalls, 1);
              expect(
                nextId,
                originalIdCount,
                reason: 'failed preparation must not mint an answer identity',
              );
              expect((await tester.runAsync(storage.snapshot))!, before);
              await _scrollTo(tester, mode, retry);
              await tester.tap(retry);
              await _until(tester, () => repository!.completedCommits == 1);
              expect(hookCalls, 2);
              expect(
                repository!.committed.single.nativeDraft!.text,
                submittedText,
                reason:
                    'retry preserves the original unsaved submission across the preparation await',
              );
              expect(
                repository!.committed.single.responseTimeMs,
                inInclusiveRange(321, 10000),
              );
            }
            if (path == 'through History') {
              final exercise = state.exercise;
              String? optionId;
              const edited = 'synthetic changed draft';
              if (exercise is DictationSession) {
                final play = find.byKey(const ValueKey('dictation-normal'));
                await _scrollTo(tester, mode, play);
                await tester.tap(play);
                await _scrollTo(
                  tester,
                  mode,
                  find.byKey(const ValueKey('dictation-response')),
                );
                await _until(
                  tester,
                  () =>
                      tester
                          .widget<TextField>(
                            find.byKey(const ValueKey('dictation-response')),
                          )
                          .enabled ==
                      true,
                );
              }
              final audioBeforeDraftSave = voice.spoken;
              if (exercise is ChoiceClozeSession) {
                optionId = exercise.choices
                    .firstWhere((choice) => choice.id != draft.optionId)
                    .id;
                final option = find.byKey(ValueKey('cloze-option-$optionId'));
                await _scrollTo(tester, mode, option);
                await tester.tap(option);
              } else {
                final response = find.byKey(
                  ValueKey('${_prefix(mode)}-response'),
                );
                await _scrollTo(tester, mode, response);
                await tester.enterText(response, edited);
              }
              final save = find.byKey(const ValueKey('native-draft-save'));
              await _scrollTo(tester, mode, save);
              expect(find.text('Unsaved changes'), findsOneWidget);
              repository!.failDraftAckOnce = true;
              await tester.tap(save);
              await _until(
                tester,
                () => find
                    .text('Draft save is not confirmed. Retry saving.')
                    .evaluate()
                    .isNotEmpty,
              );
              final unconfirmed = (await tester.runAsync(
                () => storage.session(exercise.id),
              ))!;
              expect(repository!.drafts, hasLength(1));
              expect(voice.spoken, audioBeforeDraftSave);
              expect(
                (await tester.runAsync(
                  () => storage.count('answer_attempts'),
                ))!,
                0,
              );
              await _scrollTo(tester, mode, save);
              await tester.tap(save);
              await _until(
                tester,
                () => find
                    .text('Draft saved. Answer not recorded.')
                    .evaluate()
                    .isNotEmpty,
              );
              expect(repository!.drafts, hasLength(2));
              expect(
                repository!.drafts.last.stableSerialization,
                repository!.drafts.first.stableSerialization,
              );
              final acknowledged = (await tester.runAsync(
                () => storage.session(exercise.id),
              ))!;
              expect(
                acknowledged['checkpoint_revision'],
                unconfirmed['checkpoint_revision'],
              );
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await tester.runAsync(repository!.settle);
              storage = (await tester.runAsync(storage.reopen))!;
              repository = _ResumeRepository(
                DriftLearningRepository(
                  storage.database,
                  ownerWrites: storage.ownerWrites,
                ),
              );
              learning = create(wrapped: repository);
              final restored = (await tester.runAsync(
                () => learning.resumeNativeExercise(
                  sessionId: exercise.id,
                  expectedOwnerId: configuredOwnerId,
                  stillCurrent: () => true,
                ),
              ))!;
              final savedDraft = restored.checkpoint.draft;
              expect(
                savedDraft.tileSlots,
                isNull,
                reason:
                    'editing text explicitly changes tile mode to typed mode',
              );
              expect(savedDraft.optionId, optionId);
              expect(savedDraft.text, optionId == null ? edited : '');
              expect(savedDraft.responseTimeMs, inInclusiveRange(321, 10000));
              expect(savedDraft.assisted, exercise is DictationSession);
              expect(restored.checkpoint.answer, isNull);
              expect(
                (await tester.runAsync(
                  () => storage.count('answer_attempts'),
                ))!,
                0,
              );
              expect(blockedProvider.requests, 0);
            }
            if (path == 'assistance ACK') {
              repository!.draftAckGate = Completer<void>();
              final slow = find.byKey(const ValueKey('dictation-slow'));
              await _scrollTo(tester, mode, slow);
              await tester.tap(slow);
              await _until(tester, () => repository!.drafts.length == 1);
              await _until(tester, () => repository!.completedDrafts == 1);
              expect(voice.spoken, 0);
              expect(
                voice.stopped,
                0,
                reason:
                    'assistance acknowledgement precedes every audio effect',
              );
              final row = (await tester.runAsync(
                () => storage.session(state.exercise.id),
              ))!;
              final checkpoint =
                  jsonDecode(row['checkpoint_json']! as String)
                      as Map<String, dynamic>;
              expect((checkpoint['draft'] as Map)['assisted'], isTrue);
              repository!.draftAckGate!.complete();
              await _until(tester, () => voice.spoken == 1);
              expect(voice.stopped, 1);
              // A native START acknowledgement still owns playback until stop.
              owners.add(configuredOtherOwnerId);
              await _until(tester, () => voice.stopped == 2);
              expect(repository!.drafts, hasLength(1));
              expect(
                (await tester.runAsync(
                  () => storage.count('answer_attempts'),
                ))!,
                0,
              );
            }
            if (pending || answered || closing) {
              final prefix = _prefix(mode);
              final feedback = find.byKey(ValueKey('$prefix-feedback'));
              if (pending) {
                expect(feedback, findsNothing);
                repository!.commitAckGate = Completer<void>();
                final retry = find.byKey(ValueKey('$prefix-retry'));
                await _scrollTo(tester, mode, retry);
                await tester.tap(retry);
                await _until(tester, () => repository!.completedCommits == 1);
                expect(
                  feedback,
                  findsNothing,
                  reason: 'feedback requires the answer acknowledgement',
                );
                expect(find.byType(ScoreScreen), findsNothing);
                final original = state.checkpoint.answer!;
                expect(repository!.committed.single.id, original.id);
                expect(
                  repository!.committed.single.occurredAtUtc,
                  original.occurredAtUtc,
                );
                expect(repository!.committed.single.responseTimeMs, 432);
                repository!.commitAckGate!.complete();
                await _until(tester, () => repository!.completedReads >= 2);
                await _scrollTo(tester, mode, feedback);
                expect(feedback, findsOneWidget);
              }
              repository!.finishAckGate = Completer<void>();
              final finish = find.byKey(
                ValueKey('$prefix-${closing ? 'retry' : 'finish'}'),
              );
              await _scrollTo(tester, mode, finish);
              await tester.tap(finish);
              await _until(tester, () => repository!.completedFinishes == 1);
              expect(
                find.byType(ScoreScreen),
                findsNothing,
                reason: 'result requires the finish acknowledgement',
              );
              if (closing) {
                expect(
                  repository!.finished.single.endedAtUtc,
                  state.checkpoint.endedAtUtc,
                );
              }
              repository!.finishAckGate!.complete();
              await _until(
                tester,
                () => find.byType(ScoreScreen).evaluate().isNotEmpty,
              );
              final rows = (await tester.runAsync(
                () => storage.database
                    .select(storage.database.answerAttempts)
                    .get(),
              ))!;
              expect(rows, hasLength(1));
              expect(rows.single.id, state.checkpoint.answer!.id);
              expect(
                rows.single.responseTimeMs,
                432,
                reason: 'the offline17-hour gap is excluded',
              );
              expect(
                rows.single.occurredAtUtcMs,
                state.checkpoint.answer!.occurredAtUtc.millisecondsSinceEpoch,
              );
              expect(repository!.starts, 0);
              expect(blockedProvider.requests, 0);
              expect(voice.spoken, 0);
              if (throughToday) {
                final back = find.widgetWithText(FilledButton, 'กลับหน้าเรียน');
                await tester.ensureVisible(back);
                await tester.tap(back);
                await _until(
                  tester,
                  () =>
                      find.byType(ChooseModeScreen).evaluate().isNotEmpty &&
                      find.byType(ScoreScreen).evaluate().isEmpty,
                );
                expect(find.byType(ScoreScreen), findsNothing);
              }
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            final gate = repository?.resumeAckGate;
            if (gate != null && !gate.isCompleted) gate.complete();
            for (final gate in [
              repository?.draftAckGate,
              repository?.commitAckGate,
              repository?.finishAckGate,
            ]) {
              if (gate != null && !gate.isCompleted) gate.complete();
            }
            if (repository != null) await tester.runAsync(repository!.settle);
            await tester.runAsync(owners.close);
            await motivationPresentationIo(tester, () async {
              if (opened) await storage.close();
              final resolved = await directory.resolveSymbolicLinks();
              final temp = await Directory.systemTemp.resolveSymbolicLinks();
              if (!resolved.startsWith(
                '$temp${Platform.pathSeparator}lexiquest-native-ui-resume-',
              )) {
                throw StateError('Refusing cleanup outside the resume fixture');
              }
              await directory.delete(recursive: true);
            }, stage: 'native-resume/close-database');
          }
        },
      );
    }
  }
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

String _prefix(String mode) => switch (mode) {
  'wordScramble' => 'scramble',
  'sentenceScramble' => 'sentence',
  'dictation' => 'dictation',
  _ => 'cloze',
};

Future<void> _scrollTo(WidgetTester tester, String mode, Finder target) async {
  await tester.pump();
  final lesson = switch (mode) {
    'dictation' => find.byType(DictationQuizScreen),
    'wordScramble' => find.byType(WordScrambleScreen),
    'sentenceScramble' => find.byType(SentenceScrambleScreen),
    _ => find.byType(FillInTheBlanksScreen),
  };
  final scrollable = find
      .descendant(of: lesson, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  if (target.evaluate().isEmpty) {
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
  }
  for (var attempt = 0; attempt < 40 && target.evaluate().isEmpty; attempt++) {
    final bounds = tester.getRect(scrollable);
    await tester.dragFrom(
      Offset(bounds.left + 8, bounds.center.dy),
      const Offset(0, -180),
    );
    position.jumpTo(position.pixels);
    await tester.pump();
  }
  expect(
    target,
    findsOneWidget,
    reason:
        'mode=$mode target=$target offset=${position.pixels} '
        'maxScrollExtent=${position.maxScrollExtent} '
        'viewport=${tester.getRect(scrollable)}',
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'the current lesson target must be inside the actual viewport',
  );
}

NativeAnswerInput _correctInput(AcceptedNativeExercise exercise) {
  const elapsed = Duration(milliseconds: 432);
  return switch (exercise) {
    DictationSession() => DictationAnswerInput(
      exercise: exercise,
      response: exercise.word.spelling,
      assisted: true,
      responseTime: elapsed,
    ),
    WordScrambleSession() => WordScrambleAnswerInput(
      exercise: exercise,
      response: exercise.word.spelling,
      responseTime: elapsed,
    ),
    SentenceScrambleSession() => SentenceScrambleAnswerInput(
      exercise: exercise,
      response: exercise.content.sentence,
      responseTime: elapsed,
    ),
    TypedClozeSession() => TypedClozeAnswerInput(
      exercise: exercise,
      response: exercise.word.spelling,
      responseTime: elapsed,
    ),
    ChoiceClozeSession() => ChoiceClozeAnswerInput(
      exercise: exercise,
      optionId: exercise.word.id,
      responseTime: elapsed,
    ),
  };
}

NativeExerciseDraft _draft(AcceptedNativeExercise exercise) {
  if (exercise is ChoiceClozeSession) {
    return NativeExerciseDraft(
      optionId: exercise.choices.last.id,
      responseTimeMs: 321,
    );
  }
  if (exercise is WordScrambleSession || exercise is SentenceScrambleSession) {
    final bank = switch (exercise) {
      WordScrambleSession(:final letters) => letters,
      SentenceScrambleSession(:final content, :final tokenOrder) =>
        tokenOrder.map((index) => content.tokens[index]).toList(),
      _ => throw StateError('Synthetic tile bank unavailable'),
    };
    final slots = List<int?>.filled(bank.length, null)
      ..[1] = 0
      ..[bank.length - 1] = 1;
    return NativeExerciseDraft(
      tileSlots: slots,
      text: slots
          .whereType<int>()
          .map((index) => bank[index])
          .join(exercise is WordScrambleSession ? '' : ' '),
      responseTimeMs: 321,
    );
  }
  return NativeExerciseDraft(
    text: 'synthetic acknowledged typed draft',
    responseTimeMs: 321,
    assisted: exercise is DictationSession,
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue);
}

final class _NoRegeneration implements ContentProvider {
  var requests = 0;
  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    requests++;
    throw StateError('a restored UI must not regenerate teaching content');
  }
}

final class _Voice implements VoiceProvider {
  var spoken = 0;
  var stopped = 0;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spoken++;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopped++;
  }
}

final class _ResumeRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  _ResumeRepository(this.delegate);
  final DriftLearningRepository delegate;
  var starts = 0;
  var completedStarts = 0;
  var completedReads = 0;
  var completedResumes = 0;
  Completer<void>? resumeAckGate;
  Completer<void>? commitAckGate;
  Completer<void>? finishAckGate;
  Completer<void>? draftAckGate;
  bool failDraftAckOnce = false;
  int completedDrafts = 0;
  final drafts = <NativeCheckpoint>[];
  int completedCommits = 0;
  int completedFinishes = 0;
  final committed = <RecordAnswerCommand>[];
  final finished = <NativeFinishIntent>[];
  final pending = <Future<void>>{};
  Future<T> _track<T>(Future<T> Function() operation) async {
    final done = Completer<void>();
    pending.add(done.future);
    try {
      return await operation();
    } finally {
      pending.remove(done.future);
      done.complete();
    }
  }

  Future<void> settle() async {
    await Future.wait(pending.toList());
  }

  @override
  Future<bool> hasAmbientTransaction() => delegate.hasAmbientTransaction();
  @override
  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    starts++;
    final result = await delegate.startNativeExercise(
      exercise,
      stillCurrent: stillCurrent,
    );
    completedStarts++;
    return result;
  });
  @override
  Future<NativeExerciseState> resumeNativeExercise({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _track(() async {
    final result = await delegate.resumeNativeExercise(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      stillCurrent: stillCurrent,
    );
    completedResumes++;
    await resumeAckGate?.future;
    return result;
  });
  @override
  Future<NativeExerciseState> readNativeExerciseState(
    AcceptedNativeExercise exercise, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    final result = await delegate.readNativeExerciseState(
      exercise,
      stillCurrent: stillCurrent,
    );
    completedReads++;
    return result;
  });
  @override
  Future<NativeExerciseState> saveNativeCheckpoint(
    NativeExerciseState state,
    NativeCheckpoint checkpoint, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    drafts.add(checkpoint);
    final result = await delegate.saveNativeCheckpoint(
      state,
      checkpoint,
      stillCurrent: stillCurrent,
    );
    completedDrafts++;
    await draftAckGate?.future;
    if (failDraftAckOnce) {
      failDraftAckOnce = false;
      throw StateError('Synthetic draft acknowledgement lost');
    }
    return result;
  });
  @override
  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    committed.add(command);
    final result = await delegate.commitNativeAnswer(
      exercise,
      command,
      stillCurrent: stillCurrent,
    );
    completedCommits++;
    await commitAckGate?.future;
    return result;
  });
  @override
  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    finished.add(intent);
    final result = await delegate.finishNativeExercise(
      intent,
      stillCurrent: stillCurrent,
    );
    completedFinishes++;
    await finishAckGate?.future;
    return result;
  });
}
