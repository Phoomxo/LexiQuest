import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/wordbook_import_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/srs_review_harness.dart';

void main() {
  testWidgets(
    'owned SRS reduced-motion flip and keyboard rating keep real ACK',
    (tester) async {
      final h = (await tester.runAsync(SrsReviewHarness.open))!;
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: SrsFlashcardsScreen(
              learning: h.learning,
              expectedOwnerId: configuredOwnerId,
              ownerChanges: h.ownerChanges,
            ),
          ),
        );
        await _until(
          tester,
          () => find.byKey(const ValueKey('srs-card')).evaluate().isNotEmpty,
        );
        final flip = find.byKey(const ValueKey('srs-flip'));
        await _reveal(tester, flip);
        Focus.of(
          tester.element(
            find.descendant(of: flip, matching: find.byType(Text)).first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('srs-meaning')),
          findsOneWidget,
          reason: 'Reduced motion exposes the back without a timed flip',
        );
        final rate = find.byKey(const ValueKey('srs-got'));
        await _reveal(tester, rate);
        Focus.of(
          tester.element(
            find.descendant(of: rate, matching: find.byType(Text)).first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _until(
          tester,
          () => find.text('บันทึกแล้ว').evaluate().isNotEmpty,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          1,
        );
        final next = find.byKey(const ValueKey('srs-next'));
        await _reveal(tester, next);
        Focus.of(
          tester.element(
            find.descendant(of: next, matching: find.byType(Text)).first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _until(
          tester,
          () => find.byKey(const ValueKey('srs-flip')).evaluate().isNotEmpty,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    },
  );

  for (final entry in ['tile', 'recommendation', 'weakness']) {
    testWidgets('$entry opens the captured owner complete due deck', (
      tester,
    ) async {
      final h = (await tester.runAsync(SrsReviewHarness.open))!;
      final provider = _Voice();
      final voice = VoiceUseCases(provider);
      try {
        await _pumpEntry(tester, h, voice, entry);
        final action = _action(entry);
        await _reveal(tester, action);
        await tester.tap(action);
        await _until(
          tester,
          () => find.byKey(const ValueKey('srs-card')).evaluate().isNotEmpty,
        );
        final screen = tester.widget<SrsFlashcardsScreen>(
          find.byType(SrsFlashcardsScreen),
        );
        expect(screen.expectedOwnerId, configuredOwnerId);
        expect(screen.ownerChanges, isNotNull);
        expect(identical(screen.learning, h.learning), isTrue);
        expect(identical(screen.voice, voice), isTrue);
        expect(screen.sourceWordIds, isNull);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          1,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          0,
        );
        final session = await tester.runAsync(
          () => h.database.select(h.database.learningSessions).getSingle(),
        );
        expect(session!.ownerId, configuredOwnerId);
        expect(session.activityType, 'srsReview');
        await _until(tester, () => provider.requests.length == 1);
        final second = await tester.runAsync(
          () => (h.database.select(
            h.database.vocabularyWords,
          )..where((row) => row.id.equals(h.wordIds[1]))).getSingle(),
        );
        await _reveal(tester, find.byKey(const ValueKey('srs-flip')));
        await tester.tap(find.byKey(const ValueKey('srs-flip')));
        await tester.pumpAndSettle();
        await _reveal(tester, find.byKey(const ValueKey('srs-got')));
        await tester.tap(find.byKey(const ValueKey('srs-got')));
        await _until(
          tester,
          () => find.byKey(const ValueKey('srs-next')).evaluate().isNotEmpty,
        );
        await _reveal(tester, find.byKey(const ValueKey('srs-next')));
        await tester.tap(find.byKey(const ValueKey('srs-next')));
        await _until(
          tester,
          () => find.text(second!.spelling).evaluate().isNotEmpty,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    });

    testWidgets('$entry retained launch refuses coalesced owner ABA', (
      tester,
    ) async {
      final h = (await tester.runAsync(SrsReviewHarness.open))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      try {
        await _pumpEntry(
          tester,
          h,
          VoiceUseCases(_Voice()),
          entry,
          owners: owners.stream,
        );
        expect(_entryEnabled(tester, entry), isFalse);
        owners.add(configuredOwnerId);
        await tester.pumpAndSettle();
        expect(_entryEnabled(tester, entry), isTrue);
        final action = _action(entry);
        await _reveal(tester, action);
        final VoidCallback retained;
        if (entry == 'tile') {
          retained = tester
              .widget<ListTile>(
                find
                    .ancestor(of: action, matching: find.byType(ListTile))
                    .first,
              )
              .onTap!;
        } else if (entry == 'recommendation') {
          retained = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'ทบทวน 2 คำ'),
              )
              .onPressed!;
        } else {
          retained = tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'ทบทวนคำที่ถึงกำหนด (2)'),
              )
              .onPressed!;
        }
        owners
          ..add(null)
          ..add(configuredOwnerId);
        retained();
        await tester.pumpAndSettle();
        expect(find.byType(SrsFlashcardsScreen), findsNothing);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await owners.close();
        await tester.runAsync(h.close);
      }
    });
  }

  for (final importDeck in [false, true]) {
    testWidgets(
      '${importDeck ? 'Wordbook' : 'CEFR'} opens a read-only preview',
      (tester) async {
        final h = (await tester.runAsync(SrsReviewHarness.open))!;
        try {
          await _pumpEntry(
            tester,
            h,
            VoiceUseCases(_Voice()),
            importDeck ? 'wordbook' : 'cefr',
          );
          if (importDeck) {
            await tester.enterText(
              find.byType(TextField),
              'word,translation\nbanana,กล้วย',
            );
            await tester.tap(find.text('ประมวลผลนำเข้าคำศัพท์'));
            tester.testTextInput.hide();
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump();
            await tester.pumpAndSettle();
            final notice = tester.widget<SnackBar>(find.byType(SnackBar));
            await tester.pump(
              notice.duration + const Duration(milliseconds: 1),
            );
            await tester.pumpAndSettle();
          }
          final action = find.text(
            importDeck
                ? 'เริ่มเรียนรู้คำศัพท์ชุดนี้ทันที'
                : 'เริ่มทบทวนรายการนี้',
          );
          await _reveal(tester, action);
          final before = await tester.runAsync(h.storage.snapshot);
          await tester.tap(action);
          await _until(
            tester,
            () => find
                .byKey(const ValueKey('srs-preview-label'))
                .evaluate()
                .isNotEmpty,
          );
          final screen = tester.widget<SrsFlashcardsScreen>(
            find.byType(SrsFlashcardsScreen),
          );
          expect(screen.wordList, isNotEmpty);
          expect(screen.sourceWordIds, isNull);
          expect(find.text('บันทึกแล้ว'), findsNothing);
          expect(await tester.runAsync(h.storage.snapshot), before);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(h.close);
        }
      },
    );
  }
}

Finder _action(String entry) => find.text(switch (entry) {
  'tile' => 'ทบทวนคำศัพท์ที่ถึงกำหนด',
  'recommendation' => 'ทบทวน 2 คำ',
  _ => 'ทบทวนคำที่ถึงกำหนด (2)',
});

Future<void> _pumpEntry(
  WidgetTester tester,
  SrsReviewHarness h,
  VoiceUseCases voice,
  String entry, {
  Stream<String?>? owners,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final progress = ProgressUseCases(
    owners: h.storage.owners,
    queries: DriftProgressQueries(h.database),
    nowUtc: () => h.now,
  );
  final snapshot = ProgressSnapshot(
    sampleSize: 1,
    correctCount: 0,
    wrongCount: 1,
    accuracy: 0,
    totalXp: 0,
    completedSessions: 1,
    streakDays: 0,
    dueReviewCount: 2,
    masteredWordCount: 0,
    achievementCount: 0,
    gameLevel: 1,
    skills: [],
    recommendations: [],
    weaknesses: [
      WeaknessEvidence(
        wordId: h.wordIds.first,
        spelling: 'station',
        meaning: 'สถานี',
        sampleSize: 1,
        incorrectCount: 1,
        errorRate: 1,
        dueAtUtc: h.now,
      ),
    ],
  );
  final Widget screen = switch (entry) {
    'weakness' => WeaknessClinicScreen(
      loader: () async => snapshot,
      learning: h.learning,
      ownerChanges: owners,
    ),
    'cefr' => const CefrSelectionScreen(),
    'wordbook' => const WordbookImportScreen(),
    _ => ChooseModeScreen(
      loader: () async => snapshot,
      learning: h.learning,
      ownerChanges: owners,
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
        database: h.database,
        localOwners: h.storage.owners,
        learning: h.learning,
        progress: progress,
        voice: voice,
      ),
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
  if (owners == null &&
      ['tile', 'recommendation', 'weakness'].contains(entry)) {
    await _until(tester, () => _entryEnabled(tester, entry));
  }
}

bool _entryEnabled(WidgetTester tester, String entry) {
  final action = _action(entry);
  if (action.evaluate().isEmpty) return false;
  return switch (entry) {
    'tile' =>
      tester
              .widget<ListTile>(
                find
                    .ancestor(of: action, matching: find.byType(ListTile))
                    .first,
              )
              .onTap !=
          null,
    'recommendation' =>
      tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'ทบทวน 2 คำ'),
              )
              .onPressed !=
          null,
    _ =>
      tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'ทบทวนคำที่ถึงกำหนด (2)'),
              )
              .onPressed !=
          null,
  };
}

Future<void> _reveal(WidgetTester tester, Finder action) async {
  if (action.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      action,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      throw StateError('unused synthetic guest entry');
}

final class _Voice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}
