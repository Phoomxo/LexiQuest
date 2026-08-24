import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/widgets/rich_lexical_card.dart';

void main() {
  testWidgets(
    'shows canonical fallback and an unavailable audio state without metadata',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RichLexicalCard(word: _word())),
        ),
      );

      expect(find.text('station'), findsOneWidget);
      expect(find.text('สถานี'), findsOneWidget);
      expect(find.text('Part of speech: noun'), findsOneWidget);
      expect(find.text('CEFR: A1'), findsOneWidget);
      expect(
        find.text('Additional lexical details are unavailable.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Pronunciation audio unavailable'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'progressively reveals verified rich metadata in screen-reader order',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichLexicalCard(
              word: _word(
                metadata: RichLexicalMetadata(
                  ipa: '/ˈsteɪ.ʃən/',
                  examples: const ['The station is near the market.'],
                  synonyms: const ['terminal'],
                  antonyms: const ['departure point'],
                  audio: const LexicalAudioMetadata(
                    language: 'en',
                    assetId: 'audio:station:en',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('IPA: /ˈsteɪ.ʃən/'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Lexical entry: station. Meaning: สถานี. Part of speech: noun. CEFR: A1.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Show lexical details'));
      await tester.pump();

      expect(find.text('IPA: /ˈsteɪ.ʃən/'), findsOneWidget);
      expect(find.text('Examples'), findsOneWidget);
      expect(find.text('Synonyms: terminal'), findsOneWidget);
      expect(find.text('Antonyms: departure point'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Additional lexical details: IPA: /ˈsteɪ.ʃən/. Examples: The station is near the market.. Synonyms: terminal. Antonyms: departure point.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Pronunciation audio unavailable'),
        findsOneWidget,
      );
    },
  );

  testWidgets('bookmark action receives the pinned lexical content identity', (
    tester,
  ) async {
    ContentIdentity? bookmarked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichLexicalCard(
            word: _word(),
            bookmarkIdentity: const ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: 'word:station',
              revision: 1,
            ),
            onBookmark: (identity) async => bookmarked = identity,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Save for review'));
    await tester.pump();

    expect(
      bookmarked,
      const ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: 'word:station',
        revision: 1,
      ),
    );
  });

  testWidgets(
    'report action requires and carries the pinned lexical revision',
    (tester) async {
      ContentIdentity? reportedIdentity;
      ContentReportReason? reportedReason;
      String? reportedComment;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichLexicalCard(
              word: _word(),
              reportIdentity: const ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: 'word:station',
                revision: 1,
              ),
              onReport: ({required identity, required reason, comment}) async {
                reportedIdentity = identity;
                reportedReason = reason;
                reportedComment = comment;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Report content'));
      await tester.pumpAndSettle();
      expect(find.text('Revision 1'), findsOneWidget);
      await tester.tap(find.text('Audio problem'));
      await tester.enterText(
        find.byType(TextField),
        'Pronunciation is unclear',
      );
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(
        reportedIdentity,
        const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:station',
          revision: 1,
        ),
      );
      expect(reportedReason, ContentReportReason.audio);
      expect(reportedComment, 'Pronunciation is unclear');
    },
  );

  testWidgets('report action hides for missing or mismatched identity', (
    tester,
  ) async {
    Future<void> report({
      required ContentIdentity identity,
      required ContentReportReason reason,
      String? comment,
    }) async {}

    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: <Widget>[
            RichLexicalCard(word: _word(), onReport: report),
            RichLexicalCard(
              word: _word(),
              reportIdentity: const ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: 'word:different',
                revision: 1,
              ),
              onReport: report,
            ),
            RichLexicalCard(
              word: _word(),
              reportIdentity: const ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: 'word:station',
                revision: 2,
              ),
              onReport: report,
            ),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('Report content'), findsNothing);
  });

  testWidgets(
    'supports 200 percent text without overflow and optional audio callback',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var playCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichLexicalCard(
                word: _word(
                  metadata: RichLexicalMetadata(
                    examples: const ['The station is near the market.'],
                    audio: const LexicalAudioMetadata(
                      language: 'en',
                      assetId: 'audio:station:en',
                    ),
                  ),
                ),
                onPlayAudio: () => playCalls += 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Show lexical details'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Play pronunciation audio'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.bySemanticsLabel('Play pronunciation audio'));
      expect(playCalls, 1);
    },
  );
}

VocabularyWord _word({RichLexicalMetadata? metadata}) => VocabularyWord(
  id: 'word:station',
  ownerId: 'packaged-owner',
  categoryId: 'category:pack',
  spelling: 'station',
  normalizedSpelling: 'station',
  meaning: 'สถานี',
  normalizedMeaning: 'สถานี',
  partOfSpeech: 'noun',
  cefrLevel: 'A1',
  source: 'pack:v1',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 24),
  updatedAtUtc: DateTime.utc(2026, 8, 24),
  contentRevision: 1,
  contentChecksumSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: metadata,
);
