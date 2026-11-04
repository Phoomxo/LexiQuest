import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart';

void main() {
  for (final mode in ['typed', 'choice', 'sentence']) {
    testWidgets(
      'offline $mode starts from Home and completes one canonical answer',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final h = await motivationPresentationIo(
          tester,
          LearningPackUiHarness.open,
        );
        try {
          await motivationPresentationIo(
            tester,
            () => h.seed(bundledStarterPack),
          );
          final dependencies = AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _OfflineGuest(),
            database: h.database,
            localOwners: h.learning.owners,
            learning: h.learning,
            learningPacks: h.packs,
            progress: ProgressUseCases(
              owners: h.learning.owners,
              queries: DriftProgressQueries(h.database),
              nowUtc: () => DateTime.utc(2026, 11, 1),
            ),
            vocabulary: VocabularyUseCases(
              owners: h.learning.owners,
              vocabulary: DriftVocabularyRepository(h.database),
              generateId: () => 'synthetic-unused-vocabulary-command',
              nowUtc: () => DateTime.utc(2026, 11, 1),
            ),
          );
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: dependencies,
              child: const MaterialApp(home: ChooseModeScreen()),
            ),
          );
          await _ready(
            tester,
            () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
          );
          await tester.pumpAndSettle();
          final entry = find.byKey(
            ValueKey(
              mode == 'sentence' ? 'sentence-scramble-entry' : 'cloze-entry',
            ),
          );
          await tester.scrollUntilVisible(
            entry,
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await _tap(tester, entry);
          if (mode != 'sentence') {
            await _ready(
              tester,
              () => find
                  .byKey(ValueKey('cloze-variant-$mode'))
                  .evaluate()
                  .isNotEmpty,
            );
            await _tap(tester, find.byKey(ValueKey('cloze-variant-$mode')));
          }
          final category = find.ancestor(
            of: find.textContaining('แพ็กเริ่มต้น LexiQuest'),
            matching: find.byType(ListTile),
          );
          await _ready(tester, () => category.evaluate().isNotEmpty);
          await _tap(tester, category);
          final readyKey = mode == 'sentence'
              ? 'sentence-meaning-cue'
              : 'cloze-context';
          await _ready(
            tester,
            () => find.byKey(ValueKey(readyKey)).evaluate().isNotEmpty,
          );
          expect(
            await motivationPresentationIo(
              tester,
              () => h.count('learning_sessions'),
            ),
            1,
          );
          if (mode == 'sentence') {
            final screen = tester.widget<SentenceScrambleScreen>(
              find.byType(SentenceScrambleScreen),
            );
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('sentence-response')),
              150,
              scrollable: find
                  .descendant(
                    of: find.byType(SentenceScrambleScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.enterText(
              find.byKey(const ValueKey('sentence-response')),
              screen.session.content.sentence,
            );
          } else {
            final screen = tester.widget<FillInTheBlanksScreen>(
              find.byType(FillInTheBlanksScreen),
            );
            if (mode == 'typed') {
              await tester.ensureVisible(
                find.byKey(const ValueKey('cloze-response')),
              );
              await tester.enterText(
                find.byKey(const ValueKey('cloze-response')),
                screen.session.word.spelling,
              );
            } else {
              await _tap(tester, find.text(screen.session.word.spelling));
            }
          }
          await tester.pumpAndSettle();
          final prefix = mode == 'sentence' ? 'sentence' : 'cloze';
          await _tap(tester, find.byKey(ValueKey('$prefix-save')));
          final finish = find.byKey(ValueKey('$prefix-finish'));
          await _ready(tester, () => finish.evaluate().isNotEmpty);
          await _tap(tester, finish);
          await _ready(
            tester,
            () => find.byType(ScoreScreen).evaluate().isNotEmpty,
          );
          final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          expect(score.correctAnswers, 1);
          expect(score.wrongAnswers, 0);
          final facts = await motivationPresentationIo(
            tester,
            () async => (
              attempts: await h.database
                  .select(h.database.answerAttempts)
                  .get(),
              sessions: await h.database
                  .select(h.database.learningSessions)
                  .get(),
              research: await h.count('research_consents'),
              events: await h.count('events_v2'),
            ),
          );
          expect(facts.attempts, hasLength(1));
          expect(facts.sessions.single.state, 'completed');
          expect(facts.attempts.single.sessionId, score.resultSessionId);
          expect(facts.research, 0);
          expect(facts.events, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await closePackUi(tester, h);
        }
      },
    );
  }
}

Future<void> _ready(WidgetTester tester, bool Function() ready) =>
    untilPackUi(tester, ready);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.pumpAndSettle();
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
  await tester.pump(const Duration(milliseconds: 350));
}

final class _OfflineGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
