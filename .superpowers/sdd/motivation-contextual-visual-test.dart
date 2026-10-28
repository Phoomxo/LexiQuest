// Synthetic rendering fixture; actual current widgets, not device/UAT evidence.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';

import '../../test/support/accessibility_semantics_test_support.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var generatedId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'cloze-screen-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25, 9),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:travel',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await _insertWord(
      database,
      owner.id,
      'word:airport',
      'airport',
      2,
      _coreChecksum(spelling: 'airport', meaning: 'meaning'),
    );
    await _insertWord(
      database,
      owner.id,
      'word:station',
      'station',
      3,
      _coreChecksum(spelling: 'station', meaning: 'meaning'),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'screen-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f09-screen'),
    );
  });

  tearDown(() => database.close());

  for (final item in <(Size, double)>[
    (const Size(390, 844), 1),
    (const Size(360, 800), 2),
  ]) {
    testWidgets(
      'contextual practice visual ${item.$1.width} scale ${item.$2}',
      (tester) async {
        tester.view.physicalSize = item.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fonts = FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
        await fonts.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final tag = '${item.$1.width.toInt()}-text${(item.$2 * 100).toInt()}';
        Widget wrap(Widget page) => RepaintBoundary(
          key: const ValueKey('contextual-capture'),
          child: MaterialApp(
            theme: M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(item.$2)),
              child: child!,
            ),
            home: page,
          ),
        );
        await tester.pumpWidget(wrap(_screen(learning)));
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey<String>('cloze-mode-selected')),
        );
        await _visualTap(
          tester,
          find.byKey(const ValueKey<String>('cloze-mode-selected')),
        );
        await _visualCapture(tester, '$tag-01-sentence');
        await _visualTap(
          tester,
          find.byKey(
            const ValueKey<String>('cloze-option-word:airport-airport'),
          ),
        );
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        await _visualCapture(tester, '$tag-02-selected');
        await _visualTap(
          tester,
          find.byKey(const ValueKey<String>('cloze-submit-selected')),
        );
        await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));
        await tester.ensureVisible(find.text('The airport is busy.'));
        await tester.pumpAndSettle();
        await _visualCapture(tester, '$tag-03-feedback');
        await _visualTap(
          tester,
          find.byKey(const ValueKey<String>('cloze-next')),
        );
        await _pumpUntilFound(tester, find.text('The _____ closes.'));
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        await tester.pumpWidget(
          wrap(
            const WordScrambleScreen(
              word: 'mirror',
              meaning: 'กระจก',
              partOfSpeech: 'noun',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _visualCapture(tester, '$tag-04-spelling');
        final index = createStableScramble('mirror').indexOf('m');
        await _visualTap(
          tester,
          find.byKey(ValueKey<String>('word-letter-$index')),
        );
        await _visualCapture(tester, '$tag-05-spelling-selected');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

Future<void> _visualTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _visualCapture(WidgetTester tester, String name) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('contextual-capture')),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory(
        'build/verification/motivation-ui-20260908/visual/c1/contextual',
      );
      await out.create(recursive: true);
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

Widget _screen(LearningUseCases learning, {ClozeModeAdapter? adapter}) =>
    FillInTheBlanksScreen(
      categoryId: 'category:travel',
      learning: learning,
      evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
      modeAdapter: adapter ?? const ClozeModeAdapter(),
      loadLexicalWords: (_) async => _reviewedWords(),
    );

EvidenceContext _context(String json) => EvidenceContext.fromJson(
  (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>(),
);

List<VocabularyWord> _reviewedWords() => <VocabularyWord>[
  _lexicalWord(
    id: 'word:airport',
    spelling: 'airport',
    revision: 2,
    coreChecksum: _coreChecksum(spelling: 'airport', meaning: 'meaning'),
    artifactChecksum: _checksumB,
    example: 'The airport is busy.',
  ),
  _lexicalWord(
    id: 'word:station',
    spelling: 'station',
    revision: 3,
    coreChecksum: _coreChecksum(spelling: 'station', meaning: 'meaning'),
    artifactChecksum: _checksumA,
    example: 'The station closes.',
  ),
];

VocabularyWord _lexicalWord({
  required String id,
  required String spelling,
  required int revision,
  required String coreChecksum,
  required String artifactChecksum,
  required String example,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: 'meaning',
  normalizedMeaning: 'meaning',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 1),
  updatedAtUtc: DateTime.utc(2026, 8, 2),
  contentRevision: revision,
  contentChecksumSha256: coreChecksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    verifiedContentRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
    examples: <String>[example],
  ),
);

String _coreChecksum({required String spelling, required String meaning}) =>
    ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:travel',
      spelling: spelling,
      normalizedSpelling: spelling,
      meaning: meaning,
      normalizedMeaning: meaning,
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'pack',
      isGlobal: true,
    );

String _evidenceContentRevision({
  required String promptMode,
  required String wordId,
  required String spelling,
  required String meaning,
  required int revision,
  required String artifactChecksum,
}) {
  final checksum = LexicalPromptArtifactResolver.canonicalPromptChecksumSha256(
    promptMode: promptMode,
    coreChecksumSha256: _coreChecksum(spelling: spelling, meaning: meaning),
    verifiedArtifactRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
  );
  return LexicalPromptArtifactResolver.formatEvidenceContentRevision(
    promptMode: promptMode,
    wordId: wordId,
    revision: revision,
    checksumSha256: checksum,
  );
}

Future<void> _insertWord(
  AppDatabase database,
  String ownerId,
  String id,
  String spelling,
  int revision,
  String checksum,
) => database
    .into(database.vocabularyWords)
    .insert(
      VocabularyWordsCompanion.insert(
        id: id,
        ownerId: ownerId,
        categoryId: 'category:travel',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: 'meaning',
        normalizedMeaning: 'meaning',
        partOfSpeech: 'noun',
        source: const Value<String>('pack'),
        isGlobal: const Value<bool>(true),
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
        contentProvenance: Value(ContentProvenance.packaged.name),
        contentReviewState: Value(ContentReviewState.approved.name),
        contentPublicationState: Value(ContentPublicationState.published.name),
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1,
      ),
    );

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
