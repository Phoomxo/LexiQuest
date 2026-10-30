import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';

import '../support/sentence_scramble_ui_harness.dart';

void main() {
  testWidgets(
    'SentenceScrambleScreen allows word selection and sentence checking',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        expect(find.byType(SentenceScrambleScreen), findsOneWidget);
        expect(
          f.voice.spokenRequests,
          isEmpty,
          reason:
              'the original sentence is not played without an explicit request',
        );
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => f.voice.spokenRequests.isNotEmpty);
        final request = f.voice.spokenRequests.single;
        expect(request.text, f.session.content.sentence);
        expect(request.language, 'en');
        expect(request.contentType, 'sentence_scramble');
        expect(request.contentId, isNot(f.session.content.sentence));
        expect(request.contentId.length, lessThanOrEqualTo(256));
        await sentenceTap(tester, const ValueKey('sentence-stop'));
        expect(f.voice.stops, 1);

        await sentenceTap(tester, const ValueKey('sentence-token-0'));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          f.bank.first,
        );
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
        expect(
          f.repository.answers.single.evidenceContext.evidenceClass.name,
          'recreational',
        );
        expect(f.repository.answers.single.evidenceContext.hintLevel, 0);
        await sentenceTap(tester, const ValueKey('sentence-finish'));
        await sentenceUntil(tester, () => f.summary != null);
        expect(f.summary!.state, 'completed');
        expect(f.summary!.correctCount, 1);
        expect(await f.count(tester, 'answer_attempts'), 1);
      } finally {
        await f.close(tester);
      }
      expect(
        f.voice.stops,
        1,
        reason: 'already stopped playback is not stopped again on disposal',
      );
    },
  );
}
