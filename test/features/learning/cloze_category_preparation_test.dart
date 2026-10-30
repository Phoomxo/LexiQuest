import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/cloze_session_harness.dart';

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  for (final variant in ClozeVariant.values) {
    for (final state in ['deleted', 'foreign owner']) {
      test(
        '$variant spends zero generation on $state category leftovers',
        () async {
          if (state == 'deleted') {
            await h.database.customStatement(
              'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
              [configuredCategoryId],
            );
          } else {
            await h.database.customStatement(
              'UPDATE vocabulary_words SET category_id = ? WHERE owner_id = ?',
              [configuredOtherCategoryId, configuredOwnerId],
            );
          }
          final before = await h.storage.snapshot();
          expect(await h.prepare(variant, categoryId: null), isNull);
          expect(h.provider.requests, isEmpty);
          expect(await h.storage.snapshot(), before);
        },
      );
    }
  }
}
