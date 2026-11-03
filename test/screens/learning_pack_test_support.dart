import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import 'package:vocab_learning_app/features/learning_packs/data/http_learning_pack_source.dart';

Future<void> packUiReady(WidgetTester tester) async {
  await idlePackUi(tester);
  final button = find.byKey(const ValueKey('pack-import'));
  if (button.evaluate().isEmpty) await revealPackUi(tester, 'pack-import');
  await untilPackUi(
    tester,
    () =>
        button.evaluate().isNotEmpty &&
        tester.widget<ButtonStyleButton>(button).onPressed != null,
  );
}

Future<void> closePackUi(WidgetTester tester, LearningPackUiHarness h) async {
  var closed = false;
  Object? error;
  unawaited(
    h.close().then<void>(
      (_) => closed = true,
      onError: (Object failure) {
        error = failure;
        closed = true;
      },
    ),
  );
  for (var frame = 0; frame < 120 && !closed; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  if (!closed) {
    final failure = TestFailure(
      'Synthetic teardown stalled at ${h.closeStage}',
    );
    if (h.primaryError == null) throw failure;
    debugPrint('Additional teardown failure: $failure');
  }
  if (error != null) {
    if (h.primaryError == null) throw error!;
    debugPrint('Additional teardown failure: $error');
  }
}

Future<void> openPackUiDetail(WidgetTester tester) async {
  await packUiReady(tester);
  final row = find.widgetWithText(ListTile, 'Synthetic actions pack');
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.tap(row);
  await idlePackUi(tester);
}

Future<void> tapPackUi(WidgetTester tester, String key) async {
  await revealPackUi(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

Future<void> idlePackUi(WidgetTester tester) => untilPackUi(tester, () {
  final refresh = find.byKey(const ValueKey('pack-refresh'));
  return refresh.evaluate().isNotEmpty &&
      tester.widget<IconButton>(refresh).onPressed != null;
});

Future<void> revealPackUi(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(LearningPackCatalogScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    for (var index = 0; index < 60 && finder.evaluate().isEmpty; index++) {
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }
  expect(finder, findsOneWidget, reason: 'Action $key must remain reachable');
  for (var frame = 0; frame < 150; frame++) {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (finder.hitTestable().evaluate().isNotEmpty) {
      return;
    }
  }
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'Action $key must remain reachable after asynchronous content loads',
  );
}

Future<void> untilPackUi(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 150; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail(
    'Synthetic pack action did not settle: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
  );
}

LearningPack syntheticPackUiContent() => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-actions-pack',
      version: '1',
      title: 'Synthetic actions pack',
      objectives: ['Use cat in a sentence.'],
      cefrLevel: 'A1',
      language: 'en',
      meaningLanguage: 'th',
      provenance: const LearningPackProvenance(
        author: 'Synthetic author',
        source: 'Synthetic source',
        license: 'Synthetic tests only',
        attribution: 'No real publisher',
      ),
    ),
    entries: [
      LearningPackEntry(
        code: 'cat',
        spelling: 'cat',
        meaning: 'แมว',
        partOfSpeech: 'noun',
        definition: 'A small pet that meows.',
        examples: const [
          LearningPackExample(
            text: 'The cat sleeps.',
            translation: 'แมวนอนหลับ',
          ),
        ],
        memoryCue: 'Picture a sleeping cat.',
        hint: 'Listen for the final sound.',
        strategy: 'Say it, then use it in a sentence.',
      ),
    ],
  ),
);

final class LearningPackUiHarness {
  LearningPackUiHarness(
    this.database,
    this.packs,
    this.repository,
    this.learning,
    this.saved,
    this.reports,
  );
  final db.AppDatabase database;
  final LearningPackUseCases packs;
  final LearningPackUiRepository repository;
  final LearningUseCases learning;
  final SavedWordsUseCases saved;
  final WordReportUseCases reports;
  final voice = LearningPackUiVoice();
  Object? primaryError;
  String closeStage = 'not started';

  void recordFailure(Object error, StackTrace stack, WidgetTester tester) {
    primaryError = error;
    debugPrint('Original synthetic pack failure: $error\n$stack');
    debugPrint(
      'Synthetic active UI: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
    );
  }

  static Future<LearningPackUiHarness> open({bool loseAck = false}) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    for (final owner in [
      'synthetic-actions-owner',
      'synthetic-actions-other',
    ]) {
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(
              id: owner,
              createdAtUtcMs: 1,
              isActive: drift.Value(owner == 'synthetic-actions-owner'),
            ),
          );
    }
    DateTime now() => DateTime.utc(2026, 11, 1);
    var sequence = 0;
    String id() => 'synthetic-actions-command:${++sequence}';
    final writes = DriftOwnerWriteCoordinator(database, nowUtc: now);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: id,
      nowUtc: now,
    );
    final packReader = DriftLearningPackRepository(
      database: database,
      ownerWrites: writes,
    );
    final repository = LearningPackUiRepository(packReader, loseAck: loseAck);
    return LearningPackUiHarness(
      database,
      LearningPackUseCases(repository: repository, nowUtc: now, generateId: id),
      repository,
      LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          ownerWrites: writes,
          lexicalContent: packReader,
        ),
        generateId: id,
        nowUtc: now,
        buildInfo: const AppBuildInfo(
          version: '1.0.0',
          buildId: 'synthetic-pack-ui',
        ),
      ),
      SavedWordsUseCases(
        repository: DriftSavedWordsRepository(database, ownerWrites: writes),
        generateId: id,
        nowUtc: now,
      ),
      WordReportUseCases(
        repository: DriftWordReportRepository(
          database: database,
          ownerWriteCoordinator: writes,
        ),
        generateId: id,
        nowUtc: now,
      ),
    );
  }

  Widget app({
    LearningPackFilePicker? pickFile,
    HttpLearningPackSource? downloads,
    Brightness brightness = Brightness.light,
    bool largeText = false,
    FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
  }) => AppDependenciesScope(
    dependencies: AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _NoGuest(),
      database: database,
      learningPacks: packs,
      learning: learning,
      savedWords: saved,
      wordReports: reports,
      voice: VoiceUseCases(voice),
      features: features,
    ),
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? M3Theme.lightTheme
          : M3Theme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(largeText ? 2 : 1),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: LearningPackCatalogScreen(pickFile: pickFile, downloads: downloads),
    ),
  );

  Future<void> seed(LearningPack content) async {
    final scope = (await packs
        .captureOwner(stillCurrent: () => true)
        .timeout(const Duration(seconds: 5)))!;
    await packs
        .importPack(packs.prepareImport(scope: scope, pack: content))
        .timeout(const Duration(seconds: 5));
  }

  Future<StoredLearningPack> stored() async {
    final scope = (await packs.captureOwner(stillCurrent: () => true))!;
    return (await packs.list(scope)).single;
  }

  Future<void> switchOwner(String owner) => database
      .customUpdate(
        'UPDATE local_owners SET is_active = (id = ?)',
        variables: [drift.Variable<String>(owner)],
        updates: {database.localOwners},
      )
      .then((_) {});
  Future<int> count(String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS n FROM "$table"')
              .getSingle()
              .timeout(const Duration(seconds: 5)))
          .read<int>('n');
  Future<drift.QueryRow> canonicalAnswer() => database
      .customSelect(
        'SELECT a.prompt_mode,a.word_id,a.owner_id,s.activity_type,s.state '
        'FROM answer_attempts a JOIN learning_sessions s ON s.id=a.session_id',
      )
      .getSingle();
  Future<void> close() async {
    closeStage = 'packs.dispose';
    await packs.dispose();
    closeStage = 'database.close';
    await database.close();
    closeStage = 'closed';
  }
}

final class LearningPackUiRepository implements LearningPackRepository {
  LearningPackUiRepository(this.delegate, {required this.loseAck});
  final LearningPackRepository delegate;
  bool loseAck;
  final imports = <PackImportIntent>[];
  @override
  Future<StoredLearningPack> importPack(PackImportIntent intent) async {
    imports.add(intent);
    final result = await delegate.importPack(intent);
    if (loseAck) {
      loseAck = false;
      throw const PackStorageException(PackStorageFailureCode.unavailable);
    }
    return result;
  }

  @override
  Future<String?> readActiveOwnerId() => delegate.readActiveOwnerId();
  @override
  Stream<String?> watchActiveOwnerId() => delegate.watchActiveOwnerId();
  @override
  Future<List<StoredLearningPack>> list({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => delegate.list(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );
  @override
  Future<PackDetail> detail({
    required String expectedOwnerId,
    required String packVersionId,
    required bool Function() stillCurrent,
  }) => delegate.detail(
    expectedOwnerId: expectedOwnerId,
    packVersionId: packVersionId,
    stillCurrent: stillCurrent,
  );
  @override
  Future<StoredLearningPack> changeCache(PackCacheIntent intent) =>
      delegate.changeCache(intent);
  @override
  Future<CurrentLexicalContent?> currentLexical({
    required String expectedOwnerId,
    required String wordId,
    String? packVersionId,
    required bool Function() stillCurrent,
  }) => delegate.currentLexical(
    expectedOwnerId: expectedOwnerId,
    wordId: wordId,
    packVersionId: packVersionId,
    stillCurrent: stillCurrent,
  );
}

final class LearningPackUiVoice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('No synthetic pack route should create an owner.');
}
