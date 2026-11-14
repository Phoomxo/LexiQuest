import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

const _f33Offer = ValueKey<String>('srs-companion-offer');
const _f33Hint = ValueKey<String>('srs-companion-hint');
const _f33Retry = ValueKey<String>('srs-companion-retry');
const _f33Skip = ValueKey<String>('srs-companion-skip');
const _f33Unavailable = ValueKey<String>('srs-context-unavailable');

Future<void> _tapF33(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
  expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _missF33(WidgetTester tester) async {
  await tester.ensureVisible(find.text('ดูคำแปล'));
  await tester.tap(find.text('ดูคำแปล'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('ยังจำไม่ได้'));
  await tester.tap(find.text('ยังจำไม่ได้'));
  await _pumpUntil(tester, find.text('บันทึกแล้ว'));
  await _pumpUntil(tester, find.byKey(_f33Offer));
}

Future<void> _withF33(
  WidgetTester tester,
  Future<void> Function(_F33Fixture) body, {
  bool? failAfterCommit,
  Future<void>? acknowledgement,
}) async {
  final f = (await tester.runAsync(
    () => _F33Fixture.create(
      failAfterCommit: failAfterCommit,
      acknowledgement: acknowledgement,
    ),
  ))!;
  try {
    await body(f);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(f.db.close);
  }
}

Future<void> _openF33(
  WidgetTester tester,
  _F33Fixture f, {
  LearningUseCases? scopedLearning,
  bool waitForWord = true,
  String? hidden,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: const _F33Guest(),
        learning: scopedLearning ?? f.learning,
        localOwners: f.owners,
        features: BuildFeatureRegistry({
          Feature.srs: hidden == 'feature'
              ? FeatureState.hidden
              : FeatureState.enabled,
        }),
        fieldFeatures: BuildFieldFeatureRegistry({
          FieldFeature.srs: hidden == 'host'
              ? FieldFeatureState.hidden
              : FieldFeatureState.enabled,
        }),
      ),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SrsFlashcardsScreen(
                  key: const ValueKey('f33-original-review'),
                  learning: f.learning,
                  expectedOwnerId: f.ownerId,
                  voice: f.voice,
                ),
              ),
            ),
            child: const Text('เริ่ม f33 recall'),
          ),
        ),
      ),
    ),
  );
  if (find.byType(SrsFlashcardsScreen).evaluate().isEmpty) {
    await tester.tap(find.text('เริ่ม f33 recall'));
    await tester.pump();
  }
  if (waitForWord) await _pumpUntil(tester, find.text('apple'));
}

final class _F33Fixture {
  _F33Fixture(
    this.db,
    this.owners,
    this.ownerId,
    this.learning,
    this.alternativeLearning,
    this.failing,
    this.voice,
  );
  final AppDatabase db;
  final DriftLocalOwnerRepository owners;
  final String ownerId;
  final LearningUseCases learning, alternativeLearning;
  final _FailOnceRepository? failing;
  final VoiceUseCases voice;

  static Future<_F33Fixture> create({
    bool? failAfterCommit,
    Future<void>? acknowledgement,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'f33-a',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    await _seedDueWords(db, owners, ['apple']);
    final owner = await owners.getOrCreateActiveOwner();
    await db.customStatement(
      "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) "
      "VALUES ('f33-b','synthetic-f33-bound','firebaseBound',1,0)",
    );
    final delegate = DriftLearningRepository(db);
    final failing = failAfterCommit == null && acknowledgement == null
        ? null
        : _FailOnceRepository(
            delegate,
            afterCommit: failAfterCommit ?? false,
            acknowledgement: acknowledgement,
          );
    var sequence = 0;
    LearningUseCases build(LearningRepository repo) => LearningUseCases(
      owners: owners,
      repository: repo,
      generateId: () => 'f33-${++sequence}',
      nowUtc: () => DateTime.now().toUtc(),
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'f33'),
    );
    return _F33Fixture(
      db,
      owners,
      owner.id,
      build(failing ?? delegate),
      build(delegate),
      failing,
      VoiceUseCases(FakeVoiceProvider()),
    );
  }

  Future<String> rows() async {
    final names = db.allTables.map((t) => t.actualTableName).toList()..sort();
    return jsonEncode({
      for (final name in names)
        name: [
          for (final r
              in await db
                  .customSelect('SELECT * FROM $name ORDER BY rowid')
                  .get())
            r.data,
        ],
    });
  }

  Future<void> rehomeToB() async {
    var sequence = 0;
    await DriftOwnerUpgradeRepository(
      db,
      nowUtc: () => DateTime.now().toUtc(),
      generateConflictId: () => 'synthetic-f33-conflict-${sequence++}',
      generateOwnerId: () => 'unused-f33-owner',
    ).upgrade(activeOwnerId: ownerId, firebaseUid: 'synthetic-f33-bound');
  }
}

final class _F33Guest implements GuestSessionService {
  const _F33Guest();
  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SharedPreferences mock removed — SrsService dependency eliminated (Phase 0 W14-15).
  });

  testWidgets(
    'f33 a compatibility fixture cannot manufacture a durable-miss companion',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            wordList: const [
              {
                'word': 'apple',
                'translation': 'meaning-apple',
                'example': 'noun',
              },
            ],
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(tester, find.text('apple'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ยังจำไม่ได้'));
      await tester.tap(find.text('ยังจำไม่ได้'));
      await _pumpUntil(tester, find.text('ชุดตัวอย่างนี้ไม่บันทึกผล'));
      expect(find.byKey(_f33Offer), findsNothing);
    },
  );

  testWidgets(
    'f33 even a committed miss waits for ACK before offering a companion',
    (tester) async {
      final acknowledgement = (await tester.runAsync(
        () async => Completer<void>(),
      ))!;
      try {
        await _withF33(tester, (f) async {
          await _openF33(tester, f);
          await tester.tap(find.text('ดูคำแปล'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('ยังจำไม่ได้'));
          await tester.tap(find.text('ยังจำไม่ได้'));
          await tester.pump();
          for (var i = 0; i < 60 && !f.failing!.awaitingAcknowledgement; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(f.failing!.awaitingAcknowledgement, isTrue);
          final attempt = (await tester.runAsync(
            () => f.db.select(f.db.answerAttempts).getSingle(),
          ))!;
          expect(attempt.isCorrect, isFalse);
          expect(find.byKey(_f33Offer), findsNothing);
          expect(find.text('บันทึกแล้ว'), findsNothing);
          final before = (await tester.runAsync(f.rows))!;
          acknowledgement.complete();
          await _pumpUntil(tester, find.byKey(_f33Offer));
          expect((await tester.runAsync(f.rows))!, before);
        }, acknowledgement: acknowledgement.future);
      } finally {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      }
    },
  );

  testWidgets(
    'f33 hint is opt-in after a durable miss and skip adds no evidence',
    (tester) async {
      await _withF33(tester, (f) async {
        await _openF33(tester, f);
        expect(find.byKey(_f33Offer), findsNothing);
        await _missF33(tester);
        final before = (await tester.runAsync(f.rows))!;
        final original = (await tester.runAsync(
          () => f.db.select(f.db.answerAttempts).getSingle(),
        ))!;
        expect(original.isCorrect, isFalse);
        expect(find.byKey(_f33Hint), findsNothing);
        await _tapF33(tester, _f33Offer);
        await _pumpUntil(tester, find.byKey(_f33Hint));
        expect(
          find.descendant(
            of: find.byKey(_f33Hint),
            matching: find.textContaining('apple'),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: find.byKey(_f33Hint),
            matching: find.textContaining('noun'),
          ),
          findsWidgets,
        );
        expect((await tester.runAsync(f.rows))!, before);
        await _tapF33(tester, _f33Skip);
        expect(find.byKey(_f33Hint), findsNothing);
        expect((await tester.runAsync(f.rows))!, before);
        expect(
          (await tester.runAsync(
            () => f.db.select(f.db.pointsLedgerEntries).get(),
          ))!,
          isEmpty,
        );
        expect(
          (await tester.runAsync(
            () => f.db.select(f.db.rewardTransactions).get(),
          ))!,
          isEmpty,
        );
      });
    },
  );

  testWidgets(
    'f33 retries recall of the same word with a new attempt and preserves the original result',
    (tester) async {
      await _withF33(tester, (f) async {
        await _openF33(tester, f);
        await _missF33(tester);
        final original = (await tester.runAsync(
          () => f.db.select(f.db.answerAttempts).getSingle(),
        ))!;
        await _tapF33(tester, _f33Offer);
        await _pumpUntil(tester, find.byKey(_f33Retry));
        await _tapF33(tester, _f33Retry);
        await _pumpUntil(tester, find.text('ดูคำแปล'));
        final retry = tester.widget<SrsFlashcardsScreen>(
          find.byType(SrsFlashcardsScreen),
        );
        expect(retry.sourceWordIds, ['apple']);
        expect(retry.expectedOwnerId, f.ownerId);
        expect(find.text('meaning-apple'), findsNothing);
        expect(find.text('banana'), findsNothing);
        await tester.tap(find.text('ดูคำแปล'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('จำได้แล้ว'));
        await tester.tap(find.text('จำได้แล้ว'));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        await tester.ensureVisible(find.text('จบการฝึก'));
        await tester.tap(find.text('จบการฝึก'));
        await _pumpUntil(tester, find.text('ผลที่คุณเลือก: จำไม่ได้'));
        await tester.ensureVisible(find.text('จบการทบทวน'));
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(tester, find.byType(ScoreScreen));
        final attempts = (await tester.runAsync(
          () => f.db.select(f.db.answerAttempts).get(),
        ))!;
        expect(attempts, hasLength(2));
        expect(
          attempts.singleWhere((a) => a.id == original.id).toJson(),
          original.toJson(),
        );
        final corrected = attempts.singleWhere((a) => a.id != original.id);
        expect(
          (corrected.wordId, corrected.promptMode, corrected.isCorrect),
          ('apple', 'srsRecall', true),
        );
        expect(corrected.sessionId, isNot(original.sessionId));
        final sessions = (await tester.runAsync(
          () => f.db.select(f.db.learningSessions).get(),
        ))!;
        final parent = sessions.singleWhere((s) => s.id == original.sessionId);
        expect(
          (parent.state, parent.correctCount, parent.wrongCount, parent.score),
          ('completed', 0, 1, 0),
        );
        final child = sessions.singleWhere((s) => s.id == corrected.sessionId);
        expect(
          (
            child.state,
            child.activityType,
            child.correctCount,
            child.wrongCount,
          ),
          ('completed', 'sourcePractice', 1, 0),
        );
        final xp = (await tester.runAsync(
          () => f.db.select(f.db.pointsLedgerEntries).get(),
        ))!;
        final coins = (await tester.runAsync(
          () => f.db.select(f.db.rewardTransactions).get(),
        ))!;
        expect(xp, hasLength(1));
        expect(
          (xp.single.entryType, xp.single.amount, xp.single.sourceEventId),
          ('quizCorrect', 1, corrected.id),
        );
        expect(coins, hasLength(1));
        expect(
          (
            coins.single.transactionType,
            coins.single.amount,
            coins.single.sourceEventId,
          ),
          ('creditQuizCorrectV1', 1, corrected.id),
        );
        expect(
          (await tester.runAsync(() => f.db.select(f.db.eventsV2).get()))!,
          isEmpty,
        );
        expect(
          (await tester.runAsync(
            () => f.db.select(f.db.questClaimReceipts).get(),
          ))!,
          isEmpty,
        );
      });
    },
  );

  for (final afterCommit in [false, true]) {
    testWidgets(
      'f33 failed miss or lost ACK exposes no hint before an acknowledged exact retry afterCommit=$afterCommit',
      (tester) async {
        await _withF33(tester, (f) async {
          await _openF33(tester, f);
          await tester.tap(find.text('ดูคำแปล'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('ยังจำไม่ได้'));
          await tester.tap(find.text('ยังจำไม่ได้'));
          await _pumpUntil(
            tester,
            find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
          );
          expect(find.byKey(_f33Offer), findsNothing);
          final first = f.failing!.commands.single;
          await tester.tap(find.text('ยังจำไม่ได้'));
          await _pumpUntil(tester, find.byKey(_f33Offer));
          final second = f.failing!.commands.last;
          expect(
            (
              second.id,
              second.sessionId,
              second.wordId,
              second.occurredAtUtc,
              second.isCorrect,
            ),
            (first.id, first.sessionId, 'apple', first.occurredAtUtc, false),
          );
          final before = (await tester.runAsync(f.rows))!;
          await _tapF33(tester, _f33Offer);
          await _pumpUntil(tester, find.byKey(_f33Hint));
          await _tapF33(tester, _f33Skip);
          expect((await tester.runAsync(f.rows))!, before);
          expect(
            (await tester.runAsync(
              () => f.db.select(f.db.answerAttempts).get(),
            ))!,
            hasLength(1),
          );
          expect(
            (await tester.runAsync(
              () => f.db.select(f.db.pointsLedgerEntries).get(),
            ))!,
            isEmpty,
          );
          expect(
            (await tester.runAsync(
              () => f.db.select(f.db.rewardTransactions).get(),
            ))!,
            isEmpty,
          );
        }, failAfterCommit: afterCommit);
      },
    );
  }

  for (final stage in ['before hint', 'before retry', 'before startup']) {
    testWidgets('f33 stale A cannot use rehomed word IDs to start B $stage', (
      tester,
    ) async {
      await _withF33(tester, (f) async {
        if (stage != 'before startup') {
          await _openF33(tester, f);
          await _missF33(tester);
          if (stage == 'before retry') {
            await _tapF33(tester, _f33Offer);
            await _pumpUntil(tester, find.byKey(_f33Hint));
          }
        }
        await tester.runAsync(f.rehomeToB);
        final before = (await tester.runAsync(f.rows))!;
        if (stage == 'before startup') {
          await _openF33(tester, f, waitForWord: false);
        } else {
          await _tapF33(tester, stage == 'before hint' ? _f33Offer : _f33Retry);
        }
        await _pumpUntil(tester, find.byKey(_f33Unavailable));
        expect((await tester.runAsync(f.rows))!, before);
        expect(find.byKey(_f33Retry), findsNothing);
        expect(find.text('apple'), findsNothing);
      });
    });
  }

  testWidgets(
    'f33 changing scoped learning invalidates even an explicit retained old learning dependency',
    (tester) async {
      await _withF33(tester, (f) async {
        await _openF33(tester, f);
        await _missF33(tester);
        await _tapF33(tester, _f33Offer);
        await _pumpUntil(tester, find.byKey(_f33Hint));
        final before = (await tester.runAsync(f.rows))!;
        await _openF33(
          tester,
          f,
          scopedLearning: f.alternativeLearning,
          waitForWord: false,
        );
        await _pumpUntil(tester, find.byKey(_f33Unavailable));
        expect(find.byKey(_f33Retry), findsNothing);
        expect((await tester.runAsync(f.rows))!, before);
      });
    },
  );

  for (final hidden in ['feature', 'host']) {
    testWidgets('f33 hidden SRS $hidden creates no startup session', (
      tester,
    ) async {
      await _withF33(tester, (f) async {
        final before = (await tester.runAsync(f.rows))!;
        await _openF33(tester, f, hidden: hidden, waitForWord: false);
        await _pumpUntil(tester, find.byKey(_f33Unavailable));
        expect((await tester.runAsync(f.rows))!, before);
        expect(find.byKey(_f33Offer), findsNothing);
      });
    });
  }

  testWidgets('f33 factual hint and skip are reachable at Thai200percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    try {
      await _withF33(tester, (f) async {
        await _openF33(tester, f, textScale: 2);
        await _missF33(tester);
        await _tapF33(tester, _f33Offer);
        await _pumpUntil(tester, find.byKey(_f33Hint));
        await tester.ensureVisible(find.byKey(_f33Skip));
        expect(find.byKey(_f33Skip).hitTestable(), findsOneWidget);
        expect(
          tester.getSize(find.byKey(_f33Skip)).height,
          greaterThanOrEqualTo(48),
        );
        await _tapF33(tester, _f33Skip);
        expect(tester.takeException(), isNull);
      });
    } finally {
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('due review shows its persisted score before returning home', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'due-score',
      nowUtc: () => DateTime.utc(2026, 11, 13),
    );
    var sequence = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(db),
      generateId: () => 'due-${++sequence}',
      nowUtc: () => DateTime.utc(2026, 11, 13, 12),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    await tester.runAsync(() => _seedDueWords(db, owners, ['apple']));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SrsFlashcardsScreen(
                  learning: learning,
                  voice: VoiceUseCases(FakeVoiceProvider()),
                ),
              ),
            ),
            child: const Text('หน้าเริ่มฝึก'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('หน้าเริ่มฝึก'));
    await _pumpUntil(tester, find.text('apple'));
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำได้แล้ว'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));
    await tester.tap(find.text('จบการทบทวน'));
    await _pumpUntil(tester, find.byType(ScoreScreen));

    final sessions = await tester.runAsync(
      () => db.select(db.learningSessions).get(),
    );
    expect(sessions!.single.state, 'completed');
    expect(sessions.single.correctCount, 1);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
    await tester.pumpAndSettle();
    expect(find.text('หน้าเริ่มฝึก'), findsOneWidget);
    expect(find.byType(SrsFlashcardsScreen), findsNothing);
    expect(
      (await tester.runAsync(() => db.select(db.answerAttempts).get()))!,
      hasLength(1),
    );
  });

  testWidgets(
    'source Flashcards uses only zero-due targets with saved Again feedback at 2x',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'source',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(db),
        generateId: () => 'source',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedVocabularyWords(db, owners, ['apple', 'banana']),
      );
      expect(await db.select(db.srsStates).get(), isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SrsFlashcardsScreen(
            sourceWordIds: const ['banana'],
            learning: learning,
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(tester, find.text('บัตรคำจากเนื้อหานี้'));

      expect(find.text('banana'), findsOneWidget);
      expect(find.text('apple'), findsNothing);
      final session = await tester.runAsync(
        () => db.select(db.learningSessions).getSingle(),
      );
      expect(session!.activityType, 'sourcePractice');
      await tester.ensureVisible(find.text('ดูคำแปล'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ยังจำไม่ได้'));
      await tester.tap(find.text('ยังจำไม่ได้'));
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));

      expect(find.text('ผลที่คุณเลือก: จำไม่ได้'), findsOneWidget);
      expect(find.text('จบการฝึก'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.select(db.answerAttempts).get()),
        hasLength(1),
      );
      expect(
        await tester.runAsync(() => db.select(db.srsStates).get()),
        hasLength(1),
      );
      expect(
        await tester.runAsync(() => db.select(db.rewardTransactions).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source Flashcards returns one immutable result after finish', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'source-result',
      nowUtc: () => DateTime.utc(2026, 10, 23),
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(db),
      generateId: () => 'source-result',
      nowUtc: () => DateTime.utc(2026, 10, 23),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    await tester.runAsync(
      () => _seedVocabularyWords(db, owners, ['apple', 'banana']),
    );
    LearningSessionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute<LearningSessionResult>(
                  builder: (_) => SrsFlashcardsScreen(
                    sourceWordIds: const ['apple', 'banana'],
                    learning: learning,
                    voice: VoiceUseCases(FakeVoiceProvider()),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _pumpUntil(tester, find.text('apple'));
    await tester.tap(find.text('apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยังจำไม่ได้'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));
    await tester.tap(find.text('คำถัดไป'));
    await _pumpUntil(tester, find.text('banana'));
    await tester.tap(find.text('banana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำได้แล้ว'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));

    expect(result, isNull);
    await tester.tap(find.text('จบการฝึก'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.summary.state, 'completed');
    expect(result!.summary.correctCount, 1);
    expect(result!.summary.wrongCount, 1);
    expect(result!.mistakeWordIds, const ['apple']);
    expect(() => result!.mistakeWordIds.add('other'), throwsUnsupportedError);
  });

  testWidgets('source Flashcards load failure stays in the error UI', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'source-load-failure',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: _FailOnceRepository(
        DriftLearningRepository(db),
        afterCommit: false,
        failOnListQuizWords: true,
      ),
      generateId: () => 'source-load-failure',
      nowUtc: () => DateTime.utc(2026, 10, 21),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SrsFlashcardsScreen(
          sourceWordIds: const ['banana'],
          learning: learning,
          voice: VoiceUseCases(FakeVoiceProvider()),
        ),
      ),
    );
    await _pumpUntil(tester, find.text('เปิดข้อมูลทบทวนในเครื่องไม่สำเร็จ'));

    expect(await db.select(db.learningSessions).get(), isEmpty);
    expect(await db.select(db.answerAttempts).get(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('SRS long text at 2x can reach rating and saved Next $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'large',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: _FailOnceRepository(
          DriftLearningRepository(db),
          afterCommit: false,
        ),
        generateId: () => 'large',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedDueWords(db, owners, [
          'longsyntheticvocabularyforlargescreentext',
          'second',
        ]),
      );
      await db.customUpdate(
        "UPDATE vocabulary_words SET meaning = 'คำแปลสังเคราะห์ที่ยาวเพื่อทดสอบการเลื่อนและการขยายตัวอักษร'",
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: size.width > size.height
                ? Brightness.dark
                : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SrsFlashcardsScreen(
            learning: learning,
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        find.text('longsyntheticvocabularyforlargescreentext'),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('ดูคำแปล'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await _pumpUntil(
        tester,
        find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
      );
      expect(find.text('บันทึกแล้ว'), findsNothing);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));
      await tester.ensureVisible(find.text('คำถัดไป'));
      expect(find.text('คำถัดไป').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'SRS double rating waits for acknowledgement and Next never writes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final acknowledgement = Completer<void>();
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'pending',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final repository = _FailOnceRepository(
        DriftLearningRepository(db),
        afterCommit: false,
        acknowledgement: acknowledgement.future,
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'pending',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedDueWords(db, owners, ['apple', 'banana']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            learning: learning,
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(tester, find.text('apple'));
      await tester.tap(find.text('apple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.pump();
      expect(repository.commands, hasLength(1));
      expect(find.text('บันทึกแล้ว'), findsNothing);
      expect(find.text('คำถัดไป'), findsNothing);
      acknowledgement.complete();
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1/2'), findsOneWidget);
      final before = await tester.runAsync(
        () => db.select(db.outboxOperations).get(),
      );
      await tester.tap(find.text('คำถัดไป'));
      await _pumpUntil(tester, find.text('2/2'));
      expect(repository.commands, hasLength(1));
      expect(
        (await tester.runAsync(
          () => db.select(db.outboxOperations).get(),
        ))!.map((r) => r.toJson()),
        before!.map((r) => r.toJson()),
      );
      final credits = await tester.runAsync(
        () => db.select(db.rewardTransactions).get(),
      );
      expect(credits, hasLength(1));
      expect(credits!.single.transactionType, 'creditQuizCorrectV1');
      expect(credits.single.amount, 1);
    },
  );

  for (final (afterCommit, rating) in [
    (false, true),
    (true, true),
    (false, false),
    (true, false),
  ]) {
    testWidgets(
      'SRS retries $rating evidence after ${afterCommit ? 'lost ack' : 'failed write'}',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var sequence = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'srs-test',
          nowUtc: () => DateTime.utc(2026, 10, 20),
        );
        final delegate = DriftLearningRepository(db);
        final failing = _FailOnceRepository(delegate, afterCommit: afterCommit);
        final learning = LearningUseCases(
          owners: owners,
          repository: failing,
          generateId: () => '${sequence++}',
          nowUtc: () => DateTime.utc(2026, 10, 20, 12),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.runAsync(
          () => _seedDueWords(db, owners, ['apple', 'banana']),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SrsFlashcardsScreen(
              voice: VoiceUseCases(FakeVoiceProvider()),
              learning: learning,
            ),
          ),
        );
        await _pumpUntil(tester, find.text('apple'));
        await tester.tap(find.text('apple'));
        await tester.pumpAndSettle();
        final selectedText = rating ? 'จำได้แล้ว' : 'ยังจำไม่ได้';
        await tester.tap(find.text(selectedText));
        await _pumpUntil(
          tester,
          find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        );
        final first = failing.commands.single;
        final storedAfterFailure = await tester.runAsync(
          () => (db.select(
            db.srsStates,
          )..where((r) => r.wordId.equals('apple'))).get(),
        );
        final outboxAfterFailure = await tester.runAsync(
          () => db.select(db.outboxOperations).get(),
        );
        final wrongRating = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(rating ? 'ยังจำไม่ได้' : 'จำได้แล้ว'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.text(selectedText));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        expect(find.text('1/2'), findsOneWidget);
        expect(
          find.text('ผลที่คุณเลือก: ${rating ? 'จำได้แล้ว' : 'จำไม่ได้'}'),
          findsOneWidget,
        );
        await tester.tap(find.text('คำถัดไป'));
        await _pumpUntil(tester, find.text('2/2'));
        final second = failing.commands.last;
        expect(second.id, first.id);
        expect(second.occurredAtUtc, first.occurredAtUtc);
        expect(second.responseTimeMs, first.responseTimeMs);
        expect(second.isCorrect, first.isCorrect);
        expect(second.wordId, first.wordId);
        expect(second.sessionId, first.sessionId);
        expect(second.promptMode, first.promptMode);
        expect(second.attemptNumber, first.attemptNumber);
        expect(second.providerProvenance, first.providerProvenance);
        expect(
          wrongRating.onPressed,
          isNull,
          reason: 'an uncertain write must keep its original rating',
        );
        final attempts = await tester.runAsync(
          () => db.select(db.answerAttempts).get(),
        );
        expect(attempts, hasLength(1));
        final srs = await tester.runAsync(
          () => (db.select(
            db.srsStates,
          )..where((r) => r.wordId.equals('apple'))).get(),
        );
        expect(srs, hasLength(1));
        expect(srs!.single.repetitions, rating ? 1 : 0);
        if (afterCommit) {
          expect(srs.single.toJson(), storedAfterFailure!.single.toJson());
        }
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(rating ? 1 : 0),
        );
        expect(
          await tester.runAsync(() => db.select(db.rewardTransactions).get()),
          hasLength(rating ? 1 : 0),
        );
        if (afterCommit) {
          final outbox = await tester.runAsync(
            () => db.select(db.outboxOperations).get(),
          );
          expect(
            outbox!.map((r) => r.toJson()),
            outboxAfterFailure!.map((r) => r.toJson()),
          );
        }
        await tester.runAsync(
          () => expectLater(
            delegate.recordAnswer(
              RecordAnswerCommand(
                id: first.id,
                ownerId: first.ownerId,
                sessionId: first.sessionId,
                wordId: first.wordId,
                promptMode: first.promptMode,
                isCorrect: !first.isCorrect,
                responseTimeMs: first.responseTimeMs,
                attemptNumber: first.attemptNumber,
                occurredAtUtc: first.occurredAtUtc,
              ),
            ),
            throwsStateError,
          ),
        );
        await tester.tap(find.text('banana'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จำได้แล้ว'));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        expect(find.text('2/2'), findsOneWidget);
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(tester, find.byType(ScoreScreen));
        expect(failing.commands.last.id, isNot(first.id));
        expect(
          await tester.runAsync(() => db.select(db.answerAttempts).get()),
          hasLength(2),
        );
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(rating ? 2 : 1),
        );
        final session = await tester.runAsync(
          () => db.select(db.learningSessions).getSingle(),
        );
        expect(session!.state, 'completed');
      },
    );
  }

  for (final afterCommit in [false, true]) {
    testWidgets(
      'SRS retains last attempt when finish ${afterCommit ? 'ack is lost' : 'fails'}',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var sequence = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'srs-finish',
          nowUtc: () => DateTime.utc(2026, 10, 20),
        );
        final failing = _FailOnceRepository(
          DriftLearningRepository(db),
          afterCommit: afterCommit,
          failOnFinish: true,
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: failing,
          generateId: () => '${sequence++}',
          nowUtc: () => DateTime.utc(2026, 10, 20, 12),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.runAsync(() => _seedDueWords(db, owners, ['apple']));
        await tester.pumpWidget(
          MaterialApp(
            home: SrsFlashcardsScreen(
              voice: VoiceUseCases(FakeVoiceProvider()),
              learning: learning,
            ),
          ),
        );
        await _pumpUntil(tester, find.text('apple'));
        await tester.tap(find.text('apple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จำได้แล้ว'));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(
          tester,
          find.text('ปิดการทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        );
        final before = await tester.runAsync(
          () => db.select(db.srsStates).getSingle(),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(tester, find.byType(ScoreScreen));
        expect(failing.commands, hasLength(1));
        expect(failing.commands.last.id, failing.commands.first.id);
        expect(
          await tester.runAsync(() => db.select(db.answerAttempts).get()),
          hasLength(1),
        );
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(1),
        );
        final after = await tester.runAsync(
          () => db.select(db.srsStates).getSingle(),
        );
        expect(after!.toJson(), before!.toJson());
        final session = await tester.runAsync(
          () => db.select(db.learningSessions).getSingle(),
        );
        expect(session!.state, 'completed');
      },
    );
  }

  testWidgets('SrsFlashcardsScreen renders front side and auto-plays audio', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final wordList = [
      {
        'word': 'apple',
        'translation': 'แอปเปิ้ล',
        'example': 'An apple a day.',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SrsFlashcardsScreen(
          wordList: wordList,
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(fakeVoice.spokenRequests.length, 1);
  });

  testWidgets(
    'Tapping card flips to back side displaying translation and buttons',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final wordList = [
        {
          'word': 'banana',
          'translation': 'กล้วย',
          'example': 'Monkeys eat bananas.',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            wordList: wordList,
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card to flip
      await tester.tap(find.text('banana'));
      await tester.pumpAndSettle();

      expect(find.text('จำได้แล้ว'), findsOneWidget);
      expect(find.text('ยังจำไม่ได้'), findsOneWidget);

      // Tap Good — compatibility deck: no-op (SrsService removed Phase 0 W14-15)
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.pumpAndSettle();
      expect(find.text('ชุดตัวอย่างนี้ไม่บันทึกผล'), findsOneWidget);
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _seedDueWords(
  AppDatabase db,
  DriftLocalOwnerRepository owners,
  List<String> words,
) async {
  final owner = await owners.getOrCreateActiveOwner();
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category',
          ownerId: owner.id,
          name: 'Synthetic',
          normalizedName: 'synthetic',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final id in words) {
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: id,
            ownerId: owner.id,
            categoryId: 'category',
            spelling: id,
            normalizedSpelling: id,
            meaning: 'meaning-$id',
            normalizedMeaning: 'meaning-$id',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await db
        .into(db.srsStates)
        .insert(
          SrsStatesCompanion.insert(
            id: 'srs-$id',
            ownerId: owner.id,
            wordId: id,
            dueAtUtcMs: id == 'apple' ? 1 : 2,
            algorithmVersion: 1,
          ),
        );
  }
}

Future<void> _seedVocabularyWords(
  AppDatabase db,
  DriftLocalOwnerRepository owners,
  List<String> words,
) async {
  final owner = await owners.getOrCreateActiveOwner();
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'source-category',
          ownerId: owner.id,
          name: 'Source',
          normalizedName: 'source',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final id in words) {
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: id,
            ownerId: owner.id,
            categoryId: 'source-category',
            spelling: id,
            normalizedSpelling: id,
            meaning: 'meaning-$id',
            normalizedMeaning: 'meaning-$id',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
}

class _FailOnceRepository implements LearningRepository {
  _FailOnceRepository(
    this.delegate, {
    required this.afterCommit,
    this.failOnFinish = false,
    this.failOnListQuizWords = false,
    this.acknowledgement,
  });
  final LearningRepository delegate;
  final bool afterCommit;
  final bool failOnFinish;
  final bool failOnListQuizWords;
  final Future<void>? acknowledgement;
  bool finishFailed = false;
  bool awaitingAcknowledgement = false;
  final commands = <RecordAnswerCommand>[];

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (commands.length == 1 && !failOnFinish && acknowledgement == null) {
      if (afterCommit) await delegate.recordAnswer(command);
      throw StateError('synthetic acknowledgement/storage failure');
    }
    final result = await delegate.recordAnswer(command);
    awaitingAcknowledgement = acknowledgement != null;
    await acknowledgement;
    awaitingAcknowledgement = false;
    return result;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    Iterable<String>? normalizedSpellings,
    Iterable<String>? normalizedMeanings,
    required int? limit,
  }) {
    if (failOnListQuizWords) {
      return Future.error(StateError('synthetic source load failure'));
    }
    return delegate.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      wordIds: wordIds,
      normalizedSpellings: normalizedSpellings,
      normalizedMeanings: normalizedMeanings,
      limit: limit,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    if (failOnFinish && !finishFailed) {
      finishFailed = true;
      if (afterCommit) {
        await delegate.finishSession(
          ownerId: ownerId,
          sessionId: sessionId,
          endedAtUtc: endedAtUtc,
        );
      }
      throw StateError('synthetic finish failure');
    }
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );
  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}
