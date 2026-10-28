import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/data/drift_learner_intent_repository.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';

void main() {
  for (final imported in [false, true]) {
    for (final (label, meaning) in [
      ('ascii256', 'a' * 256),
      ('ascii257', 'a' * 257),
      ('ascii500', 'a' * 500),
      ('ascii501', 'a' * 501),
      ('thai500', 'ก' * 500),
      ('supplementary500', '😀' * 250),
      ('supplementary502', '😀' * 251),
    ]) {
      test(
        'F03 authored meaning $label imported=$imported preserves availability and identity',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          final now = DateTime.utc(2026, 9, 19);
          var next = 0;
          final owners = DriftLocalOwnerRepository(
            db,
            generateId: () => 'guest',
            nowUtc: () => now,
          );
          final vocabulary = VocabularyUseCases(
            owners: owners,
            vocabulary: DriftVocabularyRepository(db),
            generateId: () => 'v${++next}',
            nowUtc: () => now,
          );
          final category = await vocabulary.createCategory('Words');
          final accepted = meaning.length <= maxMeaningLength;
          if (imported) {
            final result =
                await ImportVocabulary(
                  owners: owners,
                  repository: DriftVocabularyImportRepository(db),
                  generateId: () => 'i${++next}',
                  nowUtc: () => now,
                )(
                  categoryId: category.id,
                  rows: [
                    {
                      'word': 'station',
                      'meaning': meaning,
                      'partOfSpeech': 'noun',
                    },
                  ],
                  sourceName: 'synthetic',
                );
            expect(result.accepted, accepted ? 1 : 0);
            expect(result.rejected.length, accepted ? 0 : 1);
          } else {
            final command = CreateWordCommand(
              categoryId: category.id,
              spelling: 'station',
              meaning: meaning,
              partOfSpeech: 'noun',
            );
            if (accepted) {
              await vocabulary.createWord(command);
            } else {
              await expectLater(
                vocabulary.createWord(command),
                throwsA(isA<InvalidVocabularyFailure>()),
              );
            }
          }
          final rows = await db.select(db.vocabularyWords).get();
          if (!accepted) {
            expect(rows, isEmpty);
            return;
          }
          final row = rows.single;
          final originalChecksum = row.contentChecksumSha256;
          expect(row.meaning, meaning);
          final identity = ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: row.id,
            revision: row.contentRevision,
          );
          await DriftLearnerIntentRepository(
            db,
            owners: owners,
            nowUtc: () => now,
          ).save(
            SaveLearningItemCommand(
              id: 'saved',
              contentIdentity: identity,
              savedAtUtc: now,
            ),
          );
          final queue = await DriftReviewCenterReader(db).compose(
            ReviewQueueFilter(
              ownerId: category.ownerId,
              evaluatedAtUtc: now,
              timezoneId: 'UTC',
            ),
          );
          expect(queue, hasLength(1));
          expect(queue.single.identity, identity);
          expect(queue.single.meaning, meaning);
          expect(queue.single.snapshot.coreChecksumSha256, originalChecksum);
          final learning = await DriftLearningRepository(db).listQuizWords(
            ownerId: category.ownerId,
            categoryId: category.id,
            limit: 10,
          );
          expect(learning.single.meaning, meaning);
          expect(learning.single.contentChecksumSha256, originalChecksum);
          expect((await db.select(db.vocabularyWords).get()).single, row);
        },
      );
    }
  }
}
