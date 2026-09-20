import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';

// This native measurement harness never opens the installed learner database.
// Host execution checks the harness only; it is not device performance evidence.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'E7 measures thirty real quiz next-item frame boundaries',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'e7-resource-owner',
        nowUtc: () => DateTime.now().toUtc(),
      );
      final owner = await owners.getOrCreateActiveOwner();
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'e7-resource-category',
              ownerId: owner.id,
              name: 'Resource fixture',
              normalizedName: 'resource fixture',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      for (var i = 0; i < 36; i++) {
        final suffix = i.toString().padLeft(2, '0');
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'word:resource-$suffix',
                ownerId: owner.id,
                categoryId: 'e7-resource-category',
                spelling: 'word$suffix',
                normalizedSpelling: 'word$suffix',
                meaning: 'meaning$suffix',
                normalizedMeaning: 'meaning$suffix',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
      }
      var nextId = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'resource-${nextId++}',
        nowUtc: () => DateTime.now().toUtc(),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'e7-resource'),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Baseline'))),
      );
      await tester.pumpAndSettle();
      debugPrintSynchronously('E7_RESOURCE_PHASE baseline');
      await Future<void>.delayed(const Duration(seconds: 3));
      final session = await learning.startQuiz(limit: 34);
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const MeaningQuizModeAdapter(),
            attachedSession: session,
          ),
        ),
      );
      await _waitFor(tester, _option(0));
      debugPrintSynchronously('E7_RESOURCE_PHASE loaded');
      await Future<void>.delayed(const Duration(seconds: 3));
      final samplesUs = <int>[];
      // Three warmups precede thirty measured transitions. Answer persistence
      // settles before timing; the sample ends after the next ready UI frame.
      for (var i = 0; i < 33; i++) {
        await tester.ensureVisible(_option(i));
        await tester.tap(_option(i));
        final next = find.byKey(const ValueKey('meaning-quiz-next'));
        await _waitFor(tester, next);
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        final watch = Stopwatch()..start();
        await tester.tap(next);
        await _waitFor(tester, _option(i + 1));
        watch.stop();
        if (i >= 3) samplesUs.add(watch.elapsedMicroseconds);
        expect(tester.takeException(), isNull);
      }
      debugPrintSynchronously('E7_RESOURCE_PHASE peak');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(samplesUs, hasLength(30));
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(33),
      );
      await learning.abandonSession(
        ownerId: owner.id,
        sessionId: session.id,
        abandonedAtUtc: DateTime.now().toUtc(),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Closed'))),
      );
      await tester.pumpAndSettle();
      debugPrintSynchronously('E7_RESOURCE_PHASE after-close');
      await Future<void>.delayed(const Duration(seconds: 3));
      final ordered = [...samplesUs]..sort();
      final result = <String, Object>{
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'platform': defaultTargetPlatform.name,
        'sampleCount': samplesUs.length,
        'samplesUs': samplesUs,
        'p50Us': ordered[14],
        'p95Us': ordered[28],
        'method':
            'Monotonic tap to first pumped frame exposing next enabled answer; '
            'real quiz, real Drift memory database; persistence outside timed span; '
            'three warmups; excludes ADB transport and does not measure raster completion.',
        'installedLearnerDatabaseOpened': false,
      };
      binding.reportData = {'e7QuizResources': result};
      debugPrintSynchronously('E7_RESOURCE_RESULT ${jsonEncode(result)}');
      expect(ordered[28], lessThanOrEqualTo(300000));
      debugPrintSynchronously('E7_RESOURCE_PASS');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Finder _option(int index) {
  final suffix = index.toString().padLeft(2, '0');
  final answer = index.isEven ? 'meaning$suffix' : 'word$suffix';
  return find.byKey(
    ValueKey('meaning-quiz-option-word:resource-$suffix-$answer'),
  );
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 10)) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(finder).onPressed != null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('Timed out waiting for enabled $finder');
}
