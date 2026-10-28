import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/category_service.dart';

final class _PartialDefaultCategoryStore implements DefaultCategoryStore {
  int remainingFailures = 1;
  final categoryIds = <String>{};
  final wordIds = <String>{};

  @override
  Future<void> ensureCategory({
    required String id,
    required String name,
    required String uid,
  }) async {
    categoryIds.add(id);
  }

  @override
  Future<void> ensureWord({
    required String categoryId,
    required String id,
    required String uid,
    required String word,
    required String meaning,
    required String partOfSpeech,
  }) async {
    wordIds.add('$categoryId/$id');
    if (remainingFailures > 0) {
      remainingFailures--;
      throw StateError('interrupted-default-seed');
    }
  }
}

void main() {
  test('constructs without resolving Firebase until default seeding runs', () {
    expect(CategoryService.new, returnsNormally);
  });

  test(
    'retries default seeding without replacing deterministic records',
    () async {
      final store = _PartialDefaultCategoryStore();
      final service = CategoryService(defaultCategoryStore: store);

      await expectLater(
        service.addDefaultCategoriesForNewUser('student-1'),
        throwsStateError,
      );
      await service.addDefaultCategoriesForNewUser('student-1');

      expect(store.categoryIds, hasLength(5));
      expect(store.wordIds, hasLength(50));
      expect(
        store.wordIds.where((id) => id == 'student-1_default_0/0'),
        hasLength(1),
      );
    },
  );
}
