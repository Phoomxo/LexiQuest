import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

import '../../support/authored_lexical_pack.dart';
import '../../support/configured_quiz_harness.dart';

void main() {
  test(
    'authored enrichment survives actual package install cache removal and personal export',
    () async {
      final h = await ConfiguredQuizHarness.open();
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: DriftLearningPackRepository(
          database: h.database,
          ownerWrites: h.ownerWrites,
        ),
        nowUtc: () => h.now,
        generateId: () => 'synthetic-rich-${++sequence}',
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final entry = LearningPackEntry(
        code: 'harbor',
        spelling: 'harbor',
        meaning: 'ท่าเรือ',
        partOfSpeech: 'noun',
        definition: 'A sheltered place for boats.',
        examples: const [
          LearningPackExample(
            text: 'The boat enters the harbor.',
            translation: 'เรือแล่นเข้าท่าเรือ',
          ),
        ],
        lexicalDetails: LearningPackLexicalDetails(
          ipa: '/ˈhɑːrbər/',
          synonyms: ['port', 'haven'],
          antonyms: ['open sea'],
        ),
      );
      final bytes = const LearningPackCodec().encode(
        metadata: authoredLexicalPack().manifest,
        entries: [entry],
      );
      final package = const LearningPackCodec().decode(bytes);
      expect(package.entries.single.canonicalJson, entry.canonicalJson);
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final installed = await packs.importPack(
        packs.prepareImport(scope: owner, pack: package, pinned: true),
      );
      final detail = await packs.detail(owner, installed.id);
      final current = (await packs.currentLexical(
        scope: owner,
        wordId: detail.bindings.single.wordId,
      ))!;
      expect(current.entry.canonicalJson, entry.canonicalJson);
      final beforeRead = await h.snapshot();
      expect(
        (await packs.currentLexical(
          scope: owner,
          wordId: current.word.id,
        ))!.entry.contentSha256,
        entry.contentSha256,
      );
      expect(await h.snapshot(), beforeRead);
      await packs.changeCache(
        packs.prepareCacheChange(
          scope: owner,
          stored: installed,
          pinned: false,
          remove: true,
        ),
      );
      final retained = (await packs.currentLexical(
        scope: owner,
        wordId: current.word.id,
      ))!;
      expect(retained.entry.canonicalJson, entry.canonicalJson);
      final exported = await DriftAccountSnapshotBuilder(
        h.database,
        nowUtc: () => h.now,
      ).build(ownerId: configuredOwnerId);
      final body = jsonDecode(utf8.decode(exported.bytes)) as Map;
      final rows = (body['data'] as Map)['lexical_content_snapshots'] as List;
      expect((rows.single as Map)['lexical_json'], entry.canonicalJson);
      expect((rows.single as Map)['lexical_sha256'], entry.contentSha256);
    },
  );
}
