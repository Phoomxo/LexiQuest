import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _GuestEntryStateStore implements AppEntryStateStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> markGuest() async {}

  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _UnavailableGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

AppBootstrap _fileBackedBootstrap(String databasePath) {
  return AppBootstrap(
    initializeFirebase: () async => throw StateError('firebase unavailable'),
    initializeSupabase: () async => throw StateError('supabase unavailable'),
    loadConfig: () => throw StateError('backend config unavailable'),
    guestSessionService: _UnavailableGuestSessionService(),
    createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
    createEntryStateStore: () async => _GuestEntryStateStore(),
  );
}

void main() {
  test(
    'production vocabulary survives a file-backed restart for only the active owner',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'lexiquest-production-vocabulary-',
      );
      final databasePath =
          '${temporaryDirectory.path}${Platform.pathSeparator}'
          'lexiquest.sqlite';
      AppDependencies? firstDependencies;
      AppDependencies? reopenedDependencies;

      try {
        firstDependencies = await _fileBackedBootstrap(
          databasePath,
        ).initialize();
        expect(firstDependencies.initialRoute, AppRoute.home);
        final activeOwner = await firstDependencies.localOwners!
            .getOrCreateActiveOwner();
        final category = await firstDependencies.vocabulary!.createCategory(
          'Travel',
        );
        final word = await firstDependencies.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
        );

        final database = firstDependencies.database!;
        final foreignCreatedAt = DateTime.utc(2026, 8, 9, 8);
        const foreignOwnerId = 'local:foreign-owner';
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: foreignOwnerId,
                createdAtUtcMs: foreignCreatedAt.millisecondsSinceEpoch,
                isActive: const Value(false),
              ),
            );
        final repository = DriftVocabularyRepository(database);
        const foreignCategoryId = 'category:foreign-travel';
        await repository.createCategory(
          VocabularyCategory(
            id: foreignCategoryId,
            ownerId: foreignOwnerId,
            name: 'Private Travel',
            normalizedName: 'private travel',
            sortOrder: 0,
            localRevision: 1,
            isDeleted: false,
            createdAtUtc: foreignCreatedAt,
            updatedAtUtc: foreignCreatedAt,
          ),
        );
        await repository.createWord(
          VocabularyWord(
            id: 'word:foreign-station',
            ownerId: foreignOwnerId,
            categoryId: foreignCategoryId,
            spelling: 'platform',
            normalizedSpelling: 'platform',
            meaning: 'ชานชาลา',
            normalizedMeaning: 'ชานชาลา',
            partOfSpeech: 'noun',
            source: 'manual',
            isGlobal: false,
            localRevision: 1,
            isDeleted: false,
            createdAtUtc: foreignCreatedAt,
            updatedAtUtc: foreignCreatedAt,
          ),
        );

        await firstDependencies.dispose();

        reopenedDependencies = await _fileBackedBootstrap(
          databasePath,
        ).initialize();
        final reopenedOwner = await reopenedDependencies.localOwners!
            .getOrCreateActiveOwner();
        final categories = await reopenedDependencies.vocabulary!
            .watchCategories()
            .first;
        final words = await reopenedDependencies.vocabulary!
            .watchWords(category.id)
            .first;

        expect(reopenedOwner.id, activeOwner.id);
        expect(categories, hasLength(1));
        expect(categories.single.id, category.id);
        expect(categories.single.ownerId, activeOwner.id);
        expect(words, hasLength(1));
        expect(words.single.id, word.id);
        expect(words.single.spelling, 'station');
        expect(words.single.meaning, 'สถานี');
        expect(words.single.categoryId, category.id);
        expect(words.single.ownerId, activeOwner.id);
      } finally {
        await reopenedDependencies?.dispose();
        await firstDependencies?.dispose();
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
