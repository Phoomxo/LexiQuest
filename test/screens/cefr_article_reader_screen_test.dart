import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/accessibility_semantics_test_support.dart';
import '../support/fail_once_learning_test_fixture.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> requests = [];

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

void main() {
  test('f13 CEFR reading declares exposure through its typed adapter', () {
    final source = File(
      'lib/screens/cefr_article_reader_screen.dart',
    ).readAsStringSync();
    expect(source, contains('CefrReadingModeAdapter'));
    expect(source, contains('_modeAdapter.evaluate()'));
  });

  testWidgets(
    'CefrArticleReaderScreen renders words and handles word tap speech',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: CefrArticleReaderScreen(
            title: 'Learning Languages',
            content: 'Practice brings great opportunity for everyone',
            cefrLevel: 'B1',
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Learning Languages'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.byType(PopScope), findsOneWidget);

      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();

      expect(fakeVoice.requests.length, 1);
      expect(fakeVoice.requests.first.text, 'Practice');
    },
  );

  testWidgets(
    'f38 final review: CEFR word and selected replay are keyboard response controls',
    (tester) => withAccessibilitySemantics(tester, () async {
      final provider = FakeVoiceProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: CefrArticleReaderScreen(
              title: 'Learning Languages',
              content: 'Practice brings opportunity',
              cefrLevel: 'B1',
              voice: voice,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final root = find.byType(CefrArticleReaderScreen);
        final practice = find.text('Practice');
        expectInsideAccessibilityRole(
          scope: root,
          descendant: practice,
          role: AccessibilitySemanticRole.responseAndInput,
          reason: 'per-word replay is an input action, not prompt-only text',
        );
        final wordFocus = Focus.of(tester.element(practice));
        wordFocus.requestFocus();
        await tester.pump();
        expect(wordFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(provider.requests.map((request) => request.text), <String>[
          'Practice',
        ]);

        await tester.tap(find.text('brings'));
        await tester.pumpAndSettle();
        expect(provider.requests.last.text, 'brings');
        final selectedReplay = find.byIcon(Icons.volume_up);
        expect(selectedReplay, findsOneWidget);
        expectInsideAccessibilityRole(
          scope: root,
          descendant: selectedReplay,
          role: AccessibilitySemanticRole.responseAndInput,
          reason: 'selected-word replay stays in the response region',
        );
        final selectedReplayFocus = Focus.of(tester.element(selectedReplay));
        selectedReplayFocus.requestFocus();
        await tester.pump();
        expect(selectedReplayFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(provider.requests.map((request) => request.text), <String>[
          'Practice',
          'brings',
          'brings',
        ]);
      } finally {
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();
        await voice.dispose();
      }
    }),
  );

  testWidgets(
    'f38 role completion: CEFR persistence retry is an owned response action',
    (tester) => withAccessibilitySemantics(tester, () async {
      final repository = FailOnceLearningRepository();
      final learning = buildFailOnceLearningUseCases(
        repository: repository,
        idPrefix: 'cefr-retry',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CefrArticleReaderScreen(
            title: 'Learning Languages',
            content: 'Practice brings opportunity',
            cefrLevel: 'B1',
            ownerId: 'owner-1',
            sessionId: 'session-1',
            wordId: 'word-1',
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('cefr-reading-complete')),
      );
      await tester.pump();
      await tester.pump();
      final retry = find.text('ลองบันทึกผลอีกครั้ง');
      expect(retry, findsOneWidget);
      expectInsideAccessibilityRole(
        scope: find.byType(CefrArticleReaderScreen),
        descendant: retry,
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'persistence recovery is a response action',
      );

      final first = repository.commands.single;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(2));
      expect(repository.commands.last.id, first.id);
      expect(
        repository.commands.last.evidenceContext.toJson(),
        first.evidenceContext.toJson(),
      );
    }),
  );
}
