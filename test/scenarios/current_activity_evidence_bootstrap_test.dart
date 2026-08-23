import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets(
    'AppBootstrap scope writes Quiz evidence through its shared adapter',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => AppConfig.fromValues(
          voiceApiUrl: 'https://voice.example.com',
          aiApiUrl: 'https://ai.example.com',
          isDebug: false,
        ),
        guestSessionService: _GuestSessionService(),
        createDatabase: () => database,
        createEntryStateStore: () async => _EntryStateStore(),
        buildAiTutor: (_) => throw StateError('AI intentionally unavailable'),
        buildVoice: (_) => throw StateError('voice intentionally unavailable'),
      );
      final dependencies = (await tester.runAsync(bootstrap.initialize))!;
      addTearDown(dependencies.dispose);
      final category = (await tester.runAsync(
        () => dependencies.vocabulary!.createCategory('Research'),
      ))!;
      await tester.runAsync(
        () => dependencies.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'evidence',
            meaning: 'proof',
            partOfSpeech: 'noun',
          ),
        ),
      );

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(home: QuizScreen(categoryId: category.id)),
        ),
      );
      await _pumpUntilFound(tester, find.text('evidence'));
      await tester.tap(find.text('proof'));
      await _pumpUntil(
        tester,
        () => database
            .select(database.answerAttempts)
            .get()
            .then((rows) => rows.length == 1),
      );

      final attempt = (await tester.runAsync(
        () => database.select(database.answerAttempts).getSingle(),
      ))!;
      expect(attempt.evidenceClass, EvidenceClass.recognition.name);
      expect(attempt.promptMode, 'meaningChoice');
      expect(attempt.isCorrect, isTrue);
      expect(dependencies.currentActivityEvidence, isNotNull);
      expect(
        identical(
          dependencies.currentActivityEvidence!.learning,
          dependencies.learning,
        ),
        isTrue,
      );
    },
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if ((await tester.runAsync(condition)) ?? false) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for condition');
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _EntryStateStore implements AppEntryStateStore {
  AppEntryMode _mode = AppEntryMode.signedOut;

  @override
  Future<void> clear() async => _mode = AppEntryMode.signedOut;

  @override
  Future<void> markGuest() async => _mode = AppEntryMode.guest;

  @override
  Future<AppEntryMode> read() async => _mode;
}
