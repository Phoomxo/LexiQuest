import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../../integration_test/support/native_baseline_cases.dart'
    show baselineAwait;
import 'composed_host_ui_audit_test.dart' show settleHost, tapHost;

// HOST SYNTHETIC: real bootstrap composition with in-memory DB, isolated support
// directory and no network/authentication. No production flag/source mutation.
class _NoLogin implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError('BS must not log in');
}

class _NoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _InertClient(this);
}

class _InertClient implements HttpClient {
  _InertClient(this.network);
  final _NoNetwork network;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    network.calls++;
    throw StateError('BS prohibits HTTP operations: ${invocation.memberName}');
  }
}

class _Entry implements AppEntryStateStore {
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
  @override
  Future<void> markGuest() async {}
  @override
  Future<void> clear() async {}
}

Future<Map<String, Object?>> _rows(AppDatabase db) async {
  final result = <String, Object?>{};
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  for (final table in tables) {
    final name = table.read<String>('name');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) throw StateError(name);
    result[name] =
        (await db.customSelect('SELECT * FROM $name ORDER BY 1').get())
            .map((r) => r.data)
            .toList();
  }
  return result;
}

void main() {
  for (final stage in [
    'initial',
    'feedback',
    'next',
    'pending',
    'feature',
    'dependency',
    'route',
    'close',
    'draft',
  ]) {
    const preview = true;
    testWidgets('BS exact ordinary quiz resume preserves canonical session $stage', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bs-host-synthetic-'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final network = _NoNetwork();
      final previousNetwork = HttpOverrides.current;
      HttpOverrides.global = network;
      addTearDown(() => HttpOverrides.global = previousNetwork);
      final dependencies = (await tester.runAsync(
        () => AppBootstrap(
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: () => AppConfig.fromValues(
            voiceApiUrl: 'https://voice.example.com',
            aiApiUrl: 'https://ai.example.com',
            isDebug: false,
          ),
          guestSessionService: _NoLogin(),
          createDatabase: () => AppDatabase(NativeDatabase.memory()),
          createEntryStateStore: () async => _Entry(),
          cloudSyncEnabled: false,
          learningPreviewEnabled: preview,
        ).initialize(),
      ))!;
      try {
        final db = dependencies.database!;
        expect(
          dependencies.hasComposedDependencyFor(Feature.dailyContinuity),
          isTrue,
        );
        expect(
          dependencies.features.isEnabled(Feature.dailyContinuity),
          preview,
        );
        expect(
          dependencies.features.isEnabled(Feature.researchAssessment),
          isFalse,
        );
        final owner = await baselineAwait(
          tester,
          dependencies.activeOwnerIdentities!.requireSingleActiveOwnerId,
        );
        await baselineAwait(tester, () async {
          await db
              .into(db.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'synthetic-bs-category',
                  ownerId: owner,
                  name: 'Synthetic BS',
                  normalizedName: 'synthetic bs',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          for (final word in [
            ('synthetic-bs-a', 'cat', 'แมว'),
            ('synthetic-bs-b', 'dog', 'สุนัข'),
          ]) {
            await db
                .into(db.vocabularyWords)
                .insert(
                  VocabularyWordsCompanion.insert(
                    id: word.$1,
                    ownerId: owner,
                    categoryId: 'synthetic-bs-category',
                    spelling: word.$2,
                    normalizedSpelling: word.$2,
                    meaning: word.$3,
                    normalizedMeaning: word.$3,
                    partOfSpeech: 'noun',
                    createdAtUtcMs: 1,
                    updatedAtUtcMs: 1,
                  ),
                );
          }
        });
        final session = await baselineAwait(
          tester,
          () => dependencies.learning!.startQuiz(
            ordinaryMeaning: true,
            categoryId: 'synthetic-bs-category',
            limit: stage == 'close' ? 1 : 2,
          ),
        );
        expect(session.ownerId, owner);
        expect(session.questions, hasLength(stage == 'close' ? 1 : 2));
        final original = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: dependencies.learning!,
          evidence: stage == 'draft'
              ? CurrentActivityEvidenceAdapter(
                  learning: dependencies.learning!,
                  rolloutModeProvider:
                      const ContextEvidencePolicyRolloutModeProvider(),
                )
              : dependencies.currentActivityEvidence!,
          runEvidenceOperation: stage == 'pending'
              ? (operation) async {
                  await operation();
                  throw StateError(
                    'synthetic lost acknowledgement before restart',
                  );
                }
              : null,
          completeSession: stage == 'close'
              ? (close) async {
                  await close.finish();
                  throw StateError(
                    'synthetic committed close acknowledgement lost',
                  );
                }
              : null,
        );
        Object? closeFailure;
        Object? answerFailure;
        if (['feedback', 'next', 'pending', 'close', 'draft'].contains(stage)) {
          await baselineAwait(tester, () async {
            if (stage == 'pending' || stage == 'draft') {
              try {
                await original.answer(
                  option: original.currentQuestion.correctOption,
                  responseTimeMs: 12,
                );
              } catch (error) {
                answerFailure = error;
              }
            } else {
              await original.answer(
                option: original.currentQuestion.correctOption,
                responseTimeMs: 12,
              );
              if (stage == 'next') await original.advance();
              if (stage == 'close') {
                try {
                  await original.advance();
                } catch (error) {
                  closeFailure = error;
                }
              }
            }
          });
        }
        if (stage == 'close') expect(closeFailure, isA<StateError>());
        if (stage == 'pending' || stage == 'draft') {
          expect(answerFailure, isA<StateError>());
        }
        final prompt = original.currentQuestion.prompt;
        original.dispose();
        final before = await baselineAwait(tester, () => _rows(db));
        final snapshot = await baselineAwait(
          tester,
          dependencies.todayHub!.load,
        );
        expect(snapshot.ownerId, owner);
        expect(snapshot.resumableSession!.id, session.id);
        await tester.pumpWidget(
          MyApp(dependencies: dependencies, ownsDependencies: false),
        );
        await settleHost(tester);
        await tapHost(tester, 'home/today');
        if (preview) {
          expect(find.byType(TodayHubScreen), findsOneWidget);
          await tapHost(tester, 'today-hub-resume-action');
          expect(
            tester
                // The original tab remains selected underneath the exact quiz route.
                .widget<NavigationBar>(
                  find.byType(NavigationBar, skipOffstage: false),
                )
                .selectedIndex,
            1,
          );
        }
        final after = await baselineAwait(tester, () => _rows(db));
        expect(
          after,
          before,
          reason: 'Navigation must preserve every synthetic table',
        );
        expect(network.calls, 0);
        // Required acceptance deliberately remains RED until the canonical
        // ordinary-quiz checkpoint/restore contract exists. Never skip this.
        expect(
          find.byType(QuizScreen),
          findsOneWidget,
          reason:
              'BS-RESUME-01: Today must reopen the original quiz, not only select Learning',
        );
        expect(
          tester
              .widget<QuizScreen>(find.byType(QuizScreen))
              .attachedSession
              ?.id,
          session.id,
        );
        expect(find.text(prompt), findsOneWidget);
        if (stage == 'feedback') {
          expect(
            tester
                .widget<AnswerFeedbackPanel>(find.byType(AnswerFeedbackPanel))
                .feedback
                .isCorrect,
            isTrue,
          );
          expect(
            find.byKey(const ValueKey('meaning-quiz-next')),
            findsOneWidget,
          );
        } else if (stage == 'close') {
          expect(
            find.byKey(const ValueKey('current-evidence-retry')),
            findsOneWidget,
          );
          await tapHost(tester, 'current-evidence-retry');
          expect(find.byType(ScoreScreen), findsOneWidget);
          expect(
            (await baselineAwait(
              tester,
              dependencies.todayHub!.load,
            )).resumableSession,
            isNull,
          );
        } else if (stage == 'pending') {
          expect(
            find.byKey(const ValueKey('current-evidence-retry')),
            findsOneWidget,
          );
          await tapHost(tester, 'current-evidence-retry');
          expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
          final attempts = await baselineAwait(
            tester,
            () => db.select(db.answerAttempts).get(),
          );
          expect(attempts, hasLength(1));
        } else {
          expect(find.byType(AnswerFeedbackPanel), findsNothing);
          if (stage == 'draft') {
            final q = session.ordinaryMeaningPlan!.questions.first;
            final selected = find.byKey(
              ValueKey('meaning-quiz-option-${q.word.id}-${q.correctOption}'),
            );
            final button = tester.widget<FilledButton>(selected);
            expect(
              button.style!.backgroundColor!.resolve({}),
              Theme.of(tester.element(selected)).colorScheme.primaryContainer,
            );
            expect(
              await baselineAwait(
                tester,
                () => db.select(db.answerAttempts).get(),
              ),
              isEmpty,
            );
          }
        }
        final recovery = await baselineAwait(
          tester,
          () => dependencies.learning!.loadExactActivityRecovery(
            ownerId: owner,
            sessionId: session.id,
            activityType: 'quiz',
          ),
        );
        expect(
          recovery?.checkpoint,
          isNotNull,
          reason: 'Exact persisted content and progress must be recoverable',
        );
        if (['feature', 'dependency', 'route'].contains(stage)) {
          final q = session.ordinaryMeaningPlan!.questions.first;
          final staleAction = tester
              .widget<FilledButton>(
                find.byKey(
                  ValueKey(
                    'meaning-quiz-option-${q.word.id}-${q.correctOption}',
                  ),
                ),
              )
              .onPressed!;
          final guardedBefore = await baselineAwait(tester, () => _rows(db));
          if (stage == 'feature') {
            (dependencies.features as RuntimeFeatureRegistry).emergencyOff(
              Feature.quiz,
            );
          } else if (stage == 'dependency') {
            // Same Navigator, replacement composition without Learning authority.
            final changed = AppDependencies(
              initialRoute: dependencies.initialRoute,
              runtimeStatus: dependencies.runtimeStatus,
              config: dependencies.config,
              guestSessionService: dependencies.guestSessionService,
              quest: dependencies.quest,
              experiments: dependencies.experiments,
              consents: dependencies.consents,
              experimentAssignments: dependencies.experimentAssignments,
              assignedLearningEventContext:
                  dependencies.assignedLearningEventContext,
              evidencePolicyRolloutModeProvider:
                  dependencies.evidencePolicyRolloutModeProvider,
              features: dependencies.features,
            );
            await tester.pumpWidget(
              MyApp(dependencies: changed, ownsDependencies: false),
            );
          } else {
            final navigator = Navigator.of(
              tester.element(find.byType(QuizScreen)),
            );
            // A covered route must reject a retained UI callback.
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Synthetic covering route')),
              ),
            );
          }
          await settleHost(tester);
          staleAction();
          await settleHost(tester);
          expect(await baselineAwait(tester, () => _rows(db)), guardedBefore);
        }
        expect(network.calls, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleHost(tester);
        await tester.runAsync(dependencies.dispose);
      }
    });
  }
}
