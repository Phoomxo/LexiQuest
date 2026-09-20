import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/reviewed_sentence_scramble_loader.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';

const checksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const session = QuizSession(
  id: 'session:sentence',
  ownerId: 'owner:learner',
  startedAtUtc: null,
  questions: [
    QuizQuestion(
      word: QuizWord(
        id: 'word:bag',
        categoryId: 'category:items',
        spelling: 'bag',
        meaning: 'กระเป๋า',
        partOfSpeech: 'noun',
        contentRevision: 1,
        contentChecksumSha256: checksum,
      ),
      options: [],
    ),
  ],
);

VocabularyWord lexical({
  int revision = 1,
  bool reviewed = true,
  bool deleted = false,
  bool metadata = true,
}) => VocabularyWord(
  id: 'word:bag',
  ownerId: 'owner:packaged',
  categoryId: 'category:items',
  spelling: 'bag',
  normalizedSpelling: 'bag',
  meaning: 'กระเป๋า',
  normalizedMeaning: 'กระเป๋า',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: deleted,
  createdAtUtc: DateTime.utc(2026),
  updatedAtUtc: DateTime.utc(2026),
  contentRevision: revision,
  contentChecksumSha256: checksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: reviewed
      ? ContentReviewState.approved
      : ContentReviewState.unreviewed,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: metadata
      ? RichLexicalMetadata(
          verifiedContentRevision: revision,
          verifiedArtifactChecksumSha256: checksum,
          examples: ['I carry my clothes in a bag.'],
        )
      : null,
);

void main() {
  Widget host(Future<List<VocabularyWord>> Function(Iterable<String>) loader) =>
      MaterialApp(
        home: ReviewedSentenceScrambleLoader(
          session: session,
          modeAdapter: const SentenceScrambleModeAdapter(),
          loadLexicalWords: loader,
        ),
      );

  testWidgets(
    'reviewed sentence uses pinned example and original session identity',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        host((ids) async {
          expect(ids, ['word:bag']);
          loads++;
          return [lexical()];
        }),
      );
      await tester.pumpAndSettle();
      final screen = tester.widget<SentenceScrambleScreen>(
        find.byType(SentenceScrambleScreen),
      );
      expect(screen.targetSentence, 'I carry my clothes in a bag.');
      expect(screen.ownerId, session.ownerId);
      expect(screen.sessionId, session.id);
      expect(screen.wordId, 'word:bag');
      await tester.pump();
      expect(loads, 1);
    },
  );

  for (final invalid in [
    'missing',
    'stale',
    'unreviewed',
    'deleted',
    'metadata',
    'duplicate',
    'error',
  ]) {
    testWidgets('reviewed sentence fails closed for $invalid content', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          (_) async => switch (invalid) {
            'missing' => [],
            'stale' => [lexical(revision: 2)],
            'unreviewed' => [lexical(reviewed: false)],
            'deleted' => [lexical(deleted: true)],
            'metadata' => [lexical(metadata: false)],
            'duplicate' => [lexical(), lexical()],
            _ => throw StateError('read failed'),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SentenceScrambleScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('sentence-example-unavailable')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reviewed sentence rejects a delayed prior-session response', (
    tester,
  ) async {
    final previous = Completer<List<VocabularyWord>>();
    final current = Completer<List<VocabularyWord>>();
    var calls = 0;
    Future<List<VocabularyWord>> load(Iterable<String> ids) =>
        ++calls == 1 ? previous.future : current.future;
    await tester.pumpWidget(host(load));
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewedSentenceScrambleLoader(
                session: QuizSession(
            id: 'session:new',
            ownerId: 'owner:new',
            startedAtUtc: null,
            questions: session.questions,
          ),
          modeAdapter: const SentenceScrambleModeAdapter(),
          loadLexicalWords: load,
        ),
      ),
    );
    previous.complete([lexical()]);
    await tester.pump();
    expect(find.byType(SentenceScrambleScreen), findsNothing);
    current.complete([]);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.byKey(const ValueKey('sentence-example-unavailable')),
      findsOneWidget,
    );
    expect(find.byType(SentenceScrambleScreen), findsNothing);
  });

  testWidgets(
    'reviewed sentence ignores delayed response after route disposal',
    (tester) async {
      final pending = Completer<List<VocabularyWord>>();
      await tester.pumpWidget(host((_) => pending.future));
      await tester.pumpWidget(const MaterialApp(home: Text('Left activity')));
      pending.complete([lexical()]);
      await tester.pumpAndSettle();
      expect(find.text('Left activity'), findsOneWidget);
      expect(find.byType(SentenceScrambleScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
