import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/widgets/rich_lexical_card.dart';

void main() {
  testWidgets('B07 bookmark pending is single-flight and failure can retry', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichLexicalCard(
              word: _word(),
              bookmarkIdentity: const ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: 'word:station',
                revision: 1,
              ),
              onBookmark: (_) async {
                calls++;
                if (calls == 1) await pending.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('บันทึกไว้ทบทวน'));
    await tester.tap(find.text('บันทึกไว้ทบทวน'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('กำลังบันทึก…'), findsOneWidget);
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('บันทึกไม่สำเร็จ ลองอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('บันทึกไว้ทบทวน'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('บันทึกไว้ในเครื่องแล้ว'), findsOneWidget);
  });

  testWidgets('B07 expansion is read-only and resets for replacement content', (
    tester,
  ) async {
    var actions = 0;
    final word = _word(metadata: _verifiedMetadata());
    Future<void> show(VocabularyWord value) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichLexicalCard(
                word: value,
                onPlayAudio: () => actions++,
                bookmarkIdentity: ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: value.id,
                  revision: value.contentRevision,
                ),
                onBookmark: (_) async {
                  actions++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(word);
    await tester.tap(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'));
    await tester.pump();
    expect(find.text('A place where trains stop.'), findsOneWidget);
    expect(actions, 0);
    await show(
      word.copyWith(
        contentRevision: 2,
        richMetadata: RichLexicalMetadata(
          verifiedContentRevision: 2,
          verifiedArtifactChecksumSha256:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          englishDefinition: 'A revised definition.',
        ),
      ),
    );
    expect(find.text('A revised definition.'), findsNothing);
    expect(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'), findsOneWidget);
    expect(actions, 0);
  });

  for (final state in [
    ContentReviewState.unreviewed,
    ContentReviewState.rejected,
  ]) {
    testWidgets('B07 rich card quarantines ${state.name} metadata', (
      tester,
    ) async {
      var played = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichLexicalCard(
              word: _word(metadata: _verifiedMetadata(), reviewState: state),
              onPlayAudio: () => played++,
            ),
          ),
        ),
      );
      expect(
        find.text('รายละเอียดคำศัพท์เพิ่มเติมไม่พร้อมใช้งาน'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('ฟังเสียงอ่านคำศัพท์'), findsNothing);
      expect(
        find.text('เนื้อหายังไม่ผ่านการตรวจสอบเพื่อเผยแพร่'),
        findsOneWidget,
      );
      expect(played, 0);
    });
  }
  testWidgets(
    'B07 rich card displays definition and source with approximate CEFR',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichLexicalCard(
                word: _word(metadata: _verifiedMetadata()),
                onPlayAudio: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('ที่มาเนื้อหา: pack:v1'), findsOneWidget);
      expect(
        find.text('ระดับคำศัพท์โดยประมาณ ไม่ใช่ผลประเมินผู้เรียน'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'));
      await tester.pump();
      expect(find.text('A place where trains stop.'), findsOneWidget);
      expect(find.text('เสียง: audio:station:en (en)'), findsOneWidget);
    },
  );
  testWidgets('B07 rich card rejects mismatched rich revision', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichLexicalCard(
            word: _word(
              metadata: RichLexicalMetadata(
                verifiedContentRevision: 2,
                verifiedArtifactChecksumSha256:
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ipa: '/wrong/',
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('รายละเอียดคำศัพท์เพิ่มเติมไม่พร้อมใช้งาน'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'), findsNothing);
  });

  testWidgets(
    'Task5 semantic actions share lexical bookmark report details and audio callbacks',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        ContentIdentity? bookmarked;
        ContentIdentity? reported;
        var played = 0;
        const identity = ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:station',
          revision: 1,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RichLexicalCard(
                  word: _word(
                    metadata: RichLexicalMetadata(
                      verifiedContentRevision: 1,
                      verifiedArtifactChecksumSha256:
                          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                      ipa: '/test/',
                      audio: const LexicalAudioMetadata(
                        language: 'en',
                        assetId: 'synthetic:audio',
                      ),
                    ),
                  ),
                  bookmarkIdentity: identity,
                  onBookmark: (value) async => bookmarked = value,
                  reportIdentity: identity,
                  onReport:
                      ({required identity, required reason, comment}) async =>
                          reported = identity,
                  onPlayAudio: () => played++,
                ),
              ),
            ),
          ),
        );
        Future<void> activate(String label) async {
          final finder = find.bySemanticsLabel(label);
          await tester.ensureVisible(finder);
          await tester.pump();
          final node = tester.getSemantics(finder);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }

        await activate('บันทึกไว้ทบทวน');
        expect(bookmarked, identity);
        await activate('ฟังเสียงอ่านคำศัพท์');
        expect(played, 1);
        await activate('ดูรายละเอียดคำศัพท์');
        expect(find.text('IPA: /test/'), findsOneWidget);
        await activate('ซ่อนรายละเอียดคำศัพท์');
        expect(find.text('IPA: /test/'), findsNothing);
        await activate('รายงานเนื้อหา');
        await tester.tap(find.text('ปัญหาคำตอบ'));
        await tester.pump();
        await tester.tap(find.text('ส่งรายงาน'));
        await tester.pumpAndSettle();
        expect(reported, identity);
      } finally {
        semantics.dispose();
      }
    },
  );
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
      expect(find.text('ชนิดของคำ: noun'), findsOneWidget);
      expect(find.text('CEFR: A1'), findsOneWidget);
      expect(
        find.text('รายละเอียดคำศัพท์เพิ่มเติมไม่พร้อมใช้งาน'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('เสียงอ่านคำศัพท์ไม่พร้อมใช้งาน'),
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
                  verifiedContentRevision: 1,
                  verifiedArtifactChecksumSha256:
                      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
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
          'คำศัพท์: station. ความหมาย: สถานี. ชนิดของคำ: noun. CEFR: A1.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'));
      await tester.pump();

      expect(find.text('IPA: /ˈsteɪ.ʃən/'), findsOneWidget);
      expect(find.text('ตัวอย่าง'), findsOneWidget);
      expect(find.text('คำใกล้เคียง: terminal'), findsOneWidget);
      expect(find.text('คำตรงข้าม: departure point'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'รายละเอียดคำศัพท์เพิ่มเติม: IPA: /ˈsteɪ.ʃən/. ตัวอย่าง: The station is near the market.. คำใกล้เคียง: terminal. คำตรงข้าม: departure point.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('เสียงอ่านคำศัพท์ไม่พร้อมใช้งาน'),
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

    await tester.tap(find.bySemanticsLabel('บันทึกไว้ทบทวน'));
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

      await tester.tap(find.bySemanticsLabel('รายงานเนื้อหา'));
      await tester.pumpAndSettle();
      expect(find.text('รุ่น 1'), findsOneWidget);
      await tester.tap(find.text('ปัญหาเสียง'));
      await tester.enterText(
        find.byType(TextField),
        'Pronunciation is unclear',
      );
      await tester.tap(find.text('ส่งรายงาน'));
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

    expect(find.bySemanticsLabel('รายงานเนื้อหา'), findsNothing);
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
                    verifiedContentRevision: 1,
                    verifiedArtifactChecksumSha256:
                        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
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
      await tester.tap(find.bySemanticsLabel('ดูรายละเอียดคำศัพท์'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('ฟังเสียงอ่านคำศัพท์'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.bySemanticsLabel('ฟังเสียงอ่านคำศัพท์'));
      expect(playCalls, 1);
    },
  );
}

RichLexicalMetadata _verifiedMetadata() => RichLexicalMetadata(
  verifiedContentRevision: 1,
  verifiedArtifactChecksumSha256:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  englishDefinition: 'A place where trains stop.',
  audio: const LexicalAudioMetadata(
    language: 'en',
    assetId: 'audio:station:en',
  ),
);

VocabularyWord _word({
  RichLexicalMetadata? metadata,
  ContentReviewState reviewState = ContentReviewState.approved,
}) => VocabularyWord(
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
  contentReviewState: reviewState,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: metadata,
);
