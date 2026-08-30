import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/accessibility_semantics_test_support.dart';
import '../support/fail_once_learning_test_fixture.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
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
  test('f13 sentence scramble delegates correctness to its typed adapter', () {
    final source = File(
      'lib/screens/sentence_scramble_screen.dart',
    ).readAsStringSync();
    expect(source, contains('SentenceScrambleModeAdapter'));
    expect(source, contains('_modeAdapter.evaluate('));
    expect(source, contains('_lifecycle!.complete('));
    expect(source, isNot(contains('userSentence == widget.targetSentence')));
  });

  testWidgets(
    'SentenceScrambleScreen allows word selection and sentence checking',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เรียงประโยคภาษาอังกฤษ'), findsOneWidget);
      expect(fakeVoice.spokenRequests.length, 1);
    },
  );

  testWidgets(
    'f38 ultra review: sentence selection and check stay in response region',
    (tester) async {
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(),
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            translation: 'แมวกำลังนอน',
            voice: voice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();

      final root = find.byType(SentenceScrambleScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byType(ActionChip),
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'the selected sentence is editable response state',
      );
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.widgetWithText(ElevatedButton, 'ตรวจประโยค'),
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'the canonical check action is part of the response region',
      );
    },
  );

  testWidgets('f38 final review: sentence feedback waits for durable retry', (
    tester,
  ) async {
    final repository = FailOnceLearningRepository();
    final learning = buildFailOnceLearningUseCases(
      repository: repository,
      idPrefix: 'sentence',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SentenceScrambleScreen(
          targetSentence: 'cat is sleeping',
          translation: 'แมวกำลังนอน',
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-1',
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final word in const <String>['cat', 'is', 'sleeping']) {
      await tester.tap(find.widgetWithText(ChoiceChip, word));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(ElevatedButton, 'ตรวจประโยค'));
    await tester.pump();
    await tester.pump();

    expect(repository.commands, hasLength(1));
    expect(
      find.text('ถูกต้อง! (Great job)'),
      findsNothing,
      reason: 'a failed evidence write cannot publish committed feedback',
    );
    final retry = find.text('ลองบันทึกผลอีกครั้ง');
    expect(retry, findsOneWidget);
    final first = repository.commands.single;

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(2));
    final retried = repository.commands.last;
    expect(retried.id, first.id);
    expect(retried.occurredAtUtc, first.occurredAtUtc);
    expect(retried.responseTimeMs, first.responseTimeMs);
    expect(retried.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(find.text('ถูกต้อง! (Great job)'), findsOneWidget);
    expect(retry, findsNothing);
  });

  testWidgets(
    'f38 role completion: sentence replay and retry are owned controls',
    (tester) => withAccessibilitySemantics(tester, () async {
      final repository = FailOnceLearningRepository();
      final learning = buildFailOnceLearningUseCases(
        repository: repository,
        idPrefix: 'sentence-controls',
      );
      final provider = FakeVoiceProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            translation: 'แมวกำลังนอน',
            voice: voice,
            ownerId: 'owner-1',
            sessionId: 'session-1',
            wordId: 'word-1',
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final root = find.byType(SentenceScrambleScreen);
      final replayIcon = find.byIcon(Icons.volume_up);
      expect(replayIcon, findsOneWidget);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: replayIcon,
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'audio replay is an actionable response control',
      );
      expect(
        tester.getSemantics(replayIcon).getSemanticsData().label.trim(),
        isNotEmpty,
      );
      expect(provider.spokenRequests, hasLength(1));
      await tester.tap(replayIcon);
      await tester.pumpAndSettle();
      expect(provider.spokenRequests, hasLength(2));

      for (final word in const <String>['cat', 'is', 'sleeping']) {
        await tester.tap(find.widgetWithText(ChoiceChip, word));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(ElevatedButton, 'ตรวจประโยค'));
      await tester.pump();
      await tester.pump();
      final retry = find.text('ลองบันทึกผลอีกครั้ง');
      expect(retry, findsOneWidget);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: retry,
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'the immutable evidence retry is a response action',
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

  testWidgets(
    'f38 final review: sentence feedback is ordered after real response controls',
    (tester) => withAccessibilitySemantics(tester, () async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            translation: 'แมวกำลังนอน',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'ตรวจประโยค'));
      await tester.pump();

      final root = find.byType(SentenceScrambleScreen);
      final feedback = find.text('เรียงยังไม่ถูกต้อง ลองใหม่อีกครั้ง');
      expectInsideAccessibilityRole(
        scope: root,
        descendant: feedback,
        role: AccessibilitySemanticRole.feedback,
        reason: 'the evaluated result is real feedback, not response input',
      );
      expectRenderedAccessibilityTraversal(
        tester,
        scope: root,
        roles: const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ],
      );
    }),
  );

  testWidgets(
    'f38 final review: sentence long content remains reachable at 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: SentenceScrambleScreen(
              targetSentence: List<String>.filled(
                14,
                'accessibility',
              ).join(' '),
              translation:
                  'คำแปลสำหรับประโยคยาวที่ต้องยังอ่านและโต้ตอบได้ทั้งหมด',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final firstChip = find.byType(ChoiceChip).first;
      final check = find.widgetWithText(ElevatedButton, 'ตรวจประโยค');
      expect(
        find.ancestor(of: firstChip, matching: find.byType(Scrollable)),
        findsAtLeastNWidgets(1),
        reason: 'scaled response choices must belong to the real scroll path',
      );
      expect(
        find.ancestor(of: check, matching: find.byType(Scrollable)),
        findsAtLeastNWidgets(1),
        reason: 'the check action must belong to the same scroll path',
      );
      await tester.ensureVisible(firstChip);
      await tester.pumpAndSettle();
      await tester.tap(firstChip);
      await tester.pump();
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      final checkFocus = Focus.of(tester.element(find.text('ตรวจประโยค')));
      checkFocus.requestFocus();
      await tester.pump();
      expect(checkFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        find.text('เรียงยังไม่ถูกต้อง ลองใหม่อีกครั้ง'),
        findsOneWidget,
        reason: 'the focused production check action must remain activatable',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
