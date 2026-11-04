import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/offline_reading_material.dart';

import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'examples must contain the complete target and identity pins changes',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'reading/material',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(syntheticPackUiContent()),
        );
        final scope = (await motivationPresentationIo(
          tester,
          () => h.packs.captureOwner(stillCurrent: () => true),
        ))!;
        final words = await motivationPresentationIo(
          tester,
          () => h.learning.prepareReading(),
        );
        final word = words.single;
        final original = (await motivationPresentationIo(
          tester,
          () => h.packs.currentLexical(scope: scope, wordId: word.id),
        ))!;
        CurrentLexicalContent content(List<LearningPackExample> examples) =>
            CurrentLexicalContent(
              pack: original.pack,
              content: original.content,
              word: original.word,
              binding: PackLexicalBinding(
                snapshotId: original.binding.snapshotId,
                wordId: original.binding.wordId,
                wordRevision: original.binding.wordRevision,
                word: original.binding.word,
                isCurrent: true,
                entry: LearningPackEntry(
                  code: 'cat',
                  spelling: 'cat',
                  meaning: 'แมว',
                  partOfSpeech: 'noun',
                  examples: examples,
                ),
              ),
            );
        final noMatch = ReadingMaterial([
          (
            word: word,
            lexical: content(const [
              LearningPackExample(text: 'The cats sleep.'),
            ]),
          ),
        ]);
        expect(noMatch.passageText, 'cat');
        expect(noMatch.supportedText, contains('ไม่มีประโยคตัวอย่าง'));
        final match = ReadingMaterial([
          (
            word: word,
            lexical: content(const [
              LearningPackExample(text: 'The cats sleep.'),
              LearningPackExample(text: 'The cat sleeps.'),
            ]),
          ),
        ]);
        expect(match.passageText, 'The cat sleeps.');
        expect(match.contentId, isNot(noMatch.contentId));
        const phrase = QuizWord(
          id: 'phrase',
          categoryId: 'c',
          spelling: 'ice cream',
          meaning: 'ไอศกรีม',
          partOfSpeech: 'noun',
          contentRevision: 'r',
        );
        final phraseMaterial = ReadingMaterial([
          (
            word: phrase,
            lexical: content(const [
              LearningPackExample(text: 'I like ice cream.'),
            ]),
          ),
        ]);
        expect(phraseMaterial.passageText, 'I like ice cream.');
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );

  testWidgets('Home reads the installed example and hides it on owner change', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'reading/open',
      () => tester.runAsync(LearningPackUiHarness.open),
    ))!;
    try {
      await motivationPresentationIo(
        tester,
        () => h.seed(syntheticPackUiContent()),
      );
      final base = (h.app() as AppDependenciesScope).dependencies;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
            runtimeStatus: base.runtimeStatus,
            config: null,
            guestSessionService: base.guestSessionService,
            database: h.database,
            learningPacks: h.packs,
            learning: h.learning,
            localOwners: h.learning.owners,
          ),
          child: MaterialApp(
            home: ChooseModeScreen(ownerChanges: h.packs.watchActiveOwnerId()),
          ),
        ),
      );
      await untilPackUi(
        tester,
        () => find.text('เลือกกิจกรรม').evaluate().isNotEmpty,
      );
      await tester.scrollUntilVisible(
        find.text('อ่านและทบทวนคำศัพท์'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ChooseModeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('อ่านและทบทวนคำศัพท์'));
      await tester.pump();
      await tester.tap(find.text('อ่านและทบทวนคำศัพท์'));
      await untilPackUi(
        tester,
        () => find.textContaining('The cat sleeps.').evaluate().isNotEmpty,
      );
      expect(find.textContaining('cat: แมว'), findsOneWidget);
      expect(find.textContaining('(B1)'), findsNothing);
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await untilPackUi(
        tester,
        () => find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย').evaluate().isNotEmpty,
      );
      expect(find.text('The cat sleeps.'), findsOneWidget);
      expect(find.textContaining('แมว'), findsNothing);
      await motivationPresentationIo(
        tester,
        () => h.switchOwner('synthetic-actions-other'),
      );
      await untilPackUi(
        tester,
        () => find
            .text('บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเปิดกิจกรรมใหม่')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('The cat sleeps.'), findsNothing);
    } finally {
      await closeMotivationPresentation(tester, h.close);
    }
  });
}
