import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/focus_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_focus_repository.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/focus_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _channel = MethodChannel('com.lexiquest.app/achievement_share');
const _exportChannel = MethodChannel('com.lexiquest.app/export');
const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
final _previousDay = DateTime.utc(2026, 11, 12, 9);
final _today = DateTime.utc(2026, 11, 13, 9);

void main() {
  setUpAll(tz.initializeTimeZones);

  testWidgets(
    'share preview hides the saved practice dates and can end without sharing',
    (tester) async {
      await _withMastery(tester, (calls, _) async {
        await _openMotivation(tester);
        await _expectDailyQuest(tester);
        await _tap(tester, 'การ์ดสิ่งที่ทำสำเร็จ');
        await _waitFor(tester, find.text('แสดงวันที่ฝึก'));
        expect(find.text('ฝึกต่อเนื่อง 2 วัน'), findsOneWidget);
        expect(find.textContaining('11/13/2026'), findsNothing);
        await _tap(tester, 'แสดงวันที่ฝึก');
        expect(find.textContaining('11/13/2026'), findsOneWidget);
        await _tap(tester, 'แสดงวันที่ฝึก');
        await _tap(tester, 'ดูตัวอย่างการแชร์');
        await _waitFor(tester, find.text('ซ่อนวันที่ฝึกแล้ว'));
        expect(find.textContaining('11/13/2026'), findsNothing);
        expect(find.textContaining('private-answer'), findsNothing);
        expect(calls, isEmpty);
        await _tap(tester, 'จบการดูตัวอย่าง');
        await _waitFor(tester, find.text('การ์ดสิ่งที่ทำสำเร็จ'));
        await _expectDailyQuest(tester);
        expect(find.text('ตรวจภาพก่อนแชร์'), findsNothing);
        expect(calls, isEmpty);
      });
    },
  );

  testWidgets('only explicit share hands the preview PNG to Android', (
    tester,
  ) async {
    final response = Completer<Object?>();
    try {
      await _withMastery(tester, onShare: (_) => response.future, (
        calls,
        _,
      ) async {
        await _openCard(tester);
        await _tap(tester, 'ดูตัวอย่างการแชร์');
        expect(calls, isEmpty);
        final share = find.text('แชร์ภาพ');
        await _waitFor(tester, share);
        await tester.ensureVisible(share);
        await tester.pump();
        final sharePosition = tester.getCenter(share);
        await _tap(tester, 'แชร์ภาพ');
        await _pumpUntil(tester, () => calls.isNotEmpty, 'PNG share');
        expect(calls.single.method, 'sharePng');
        final bytes = calls.single.arguments as Uint8List;
        expect(bytes.length, greaterThan(8));
        expect(bytes.take(8), _pngSignature);

        await tester.tapAt(sharePosition);
        await tester.pump();
        expect(calls, hasLength(1));
        response.completeError(PlatformException(code: 'unavailable'));
        await _waitFor(tester, find.text('เปิดเมนูแชร์ไม่สำเร็จ กรุณาลองใหม่'));
        expect(find.text('ตรวจภาพก่อนแชร์'), findsOneWidget);
        await _tap(tester, 'จบการดูตัวอย่าง');
        await _waitFor(tester, find.text('การ์ดสิ่งที่ทำสำเร็จ'));
        expect(calls, hasLength(1));
      });
    } finally {
      if (!response.isCompleted) response.complete();
    }
  });

  testWidgets('owner switch removes the previous learner’s card preview', (
    tester,
  ) async {
    await _withMastery(tester, (calls, fixture) async {
      await _openCard(tester);
      await _tap(tester, 'แสดงวันที่ฝึก');
      await _tap(tester, 'ดูตัวอย่างการแชร์');
      await _waitFor(tester, find.textContaining('11/13/2026'));
      await tester.runAsync(fixture.switchOwner);
      await _waitFor(tester, find.text('บัญชีผู้เรียนเปลี่ยนแล้ว'));
      expect(find.text('ฝึกต่อเนื่อง 2 วัน'), findsNothing);
      expect(find.textContaining('11/13/2026'), findsNothing);
      expect(find.text('แชร์ภาพ').hitTestable(), findsNothing);
      expect(calls, isEmpty);
    });
  });

  testWidgets('saving the preview honors Android picker cancellation', (
    tester,
  ) async {
    const destination = 'content://test/lexiquest-achievement.png';
    const selectionToken = 'synthetic';
    final exportMethods = <String>[];
    Uint8List? saved;
    var selections = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_exportChannel, (call) async {
      exportMethods.add(call.method);
      if (call.method == 'selectExportDestination') {
        expect(call.arguments, {
          'suggestedName': 'lexiquest-achievement.png',
          'mimeType': 'image/png',
        });
        if (++selections == 1) return null;
        return {'destination': destination, 'selectionToken': selectionToken};
      }
      expect(call.method, 'writeExportFile');
      expect(call.arguments['destination'], destination);
      expect(call.arguments['selectionToken'], selectionToken);
      saved = call.arguments['bytes'] as Uint8List;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_exportChannel, null));

    await _withMastery(tester, (calls, _) async {
      await _openCard(tester);
      await _tap(tester, 'ดูตัวอย่างการแชร์');
      await _tap(tester, 'บันทึกรูปการ์ด');
      await _pumpUntil(tester, () => selections == 1, 'Android cancel');
      final enabledSave = find.ancestor(
        of: find.text('บันทึกรูปการ์ด'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton && widget.onPressed != null,
        ),
      );
      await _waitFor(tester, enabledSave);
      expect(exportMethods, ['selectExportDestination']);
      expect(find.text('บันทึกรูปการ์ดแล้ว'), findsNothing);
      expect(calls, isEmpty);

      await _tap(tester, 'บันทึกรูปการ์ด');
      await _waitFor(tester, find.text('บันทึกรูปการ์ดแล้ว'));
      expect(exportMethods, [
        'selectExportDestination',
        'selectExportDestination',
        'writeExportFile',
      ]);
      expect(saved!.take(8), _pngSignature);
      expect(calls, isEmpty);

      await _tap(tester, 'แชร์ภาพ');
      await _pumpUntil(tester, () => calls.isNotEmpty, 'share saved preview');
      expect(calls.single.arguments, saved);
    });
  });

  testWidgets('an owner change during Android save discards the destination', (
    tester,
  ) async {
    const destination = 'content://test/lexiquest-achievement.png';
    const selectionToken = 'stale-selection';
    final exportMethods = <String>[];
    final selection = Completer<Map<String, String>?>();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_exportChannel, (call) async {
      exportMethods.add(call.method);
      if (call.method == 'selectExportDestination') return selection.future;
      expect(call.method, 'discardExportDestination');
      expect(call.arguments, {
        'destination': destination,
        'selectionToken': selectionToken,
      });
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_exportChannel, null));

    try {
      await _withMastery(tester, (calls, fixture) async {
        await _openCard(tester);
        await _tap(tester, 'ดูตัวอย่างการแชร์');
        await _tap(tester, 'บันทึกรูปการ์ด');
        await _pumpUntil(
          tester,
          () => exportMethods.isNotEmpty,
          'Android picker',
        );
        await tester.runAsync(fixture.switchOwner);
        await _waitFor(tester, find.text('บัญชีผู้เรียนเปลี่ยนแล้ว'));
        selection.complete({
          'destination': destination,
          'selectionToken': selectionToken,
        });
        await _pumpUntil(
          tester,
          () => exportMethods.length > 1,
          'discarded Android destination',
        );
        expect(exportMethods, [
          'selectExportDestination',
          'discardExportDestination',
        ]);
        expect(find.text('บันทึกรูปการ์ดแล้ว'), findsNothing);
        expect(calls, isEmpty);
      });
    } finally {
      if (!selection.isCompleted) selection.complete();
    }
  });
}

Future<void> _openCard(WidgetTester tester) async {
  await _openMotivation(tester);
  await _tap(tester, 'การ์ดสิ่งที่ทำสำเร็จ');
  await _waitFor(tester, find.text('แสดงวันที่ฝึก'));
}

Future<void> _openMotivation(WidgetTester tester) async {
  await _tap(tester, 'วางแผนการฝึก');
  await _tap(tester, 'ภารกิจและเพื่อนฝึก');
}

Future<void> _expectDailyQuest(WidgetTester tester) async {
  final sheet = find.byType(BottomSheet).last;
  final tally = find.descendant(
    of: sheet,
    matching: find.text('ตอบถูก 1 / 5 ข้อ'),
  );
  await _waitFor(tester, tally);
  expect(
    find.descendant(of: sheet, matching: find.text('ภารกิจรายวัน')),
    findsOneWidget,
  );
}

Future<void> _withMastery(
  WidgetTester tester,
  Future<void> Function(List<MethodCall>, _Fixture) body, {
  Future<Object?> Function(MethodCall)? onShare,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    return onShare?.call(call);
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  final fixture = _Fixture();
  try {
    await tester.runAsync(fixture.seed);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: fixture.dependencies,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const MasteryDashboardScreen(),
        ),
      ),
    );
    await body(calls, fixture);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    var closed = false;
    final closing = fixture.focus
        .dispose()
        .then((_) => fixture.db.close())
        .whenComplete(() => closed = true);
    unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
    await _pumpUntil(tester, () => closed, 'fixture close');
    await closing;
  }
}

class _Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  DateTime now = _previousDay;
  late TrustedQuestAnswerCatalog questCatalog;
  late final owners = DriftLocalOwnerRepository(
    db,
    generateId: () => 'synthetic-share-owner',
    nowUtc: () => now,
  );
  late final calendar = DriftStreakRepository(db, calendarVisible: () => true);
  late final streak = StreakUseCases(
    repository: calendar,
    owners: owners,
    nowUtc: () => now,
  );
  late final focus = FocusUseCases(
    repository: DriftFocusRepository(db, calendar: calendar),
    owners: owners,
    clock: _Clock(),
    generateId: () => 'unused-share-focus',
  );
  late final progress = ProgressUseCases(
    owners: owners,
    queries: DriftProgressQueries(
      db,
      streakRepository: calendar,
      questReader: DriftQuestProgressReader(db, catalog: questCatalog),
      questVisible: () => true,
    ),
    nowUtc: () => now,
  );
  late final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    database: db,
    localOwners: owners,
    focus: focus,
    streak: streak,
    progress: progress,
  );

  Future<void> seed() async {
    final owner = await owners.getOrCreateActiveOwner();
    questCatalog = await DriftQuestRepository(db).installAnswerCatalog();
    await db.customStatement(
      '''
      INSERT INTO vocabulary_categories
        (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms)
      VALUES ('set', ?, 'Private Set', 'private set', 1, 1)
      ''',
      [owner.id],
    );
    await db.customStatement(
      '''
      INSERT INTO vocabulary_words
        (id, owner_id, category_id, spelling, normalized_spelling,
         meaning, normalized_meaning, part_of_speech,
         created_at_utc_ms, updated_at_utc_ms)
      VALUES ('word', ?, 'set', 'private-answer', 'private-answer',
              'private-meaning', 'private-meaning', 'noun', 1, 1)
      ''',
      [owner.id],
    );
    var id = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        db,
        questCatalog: questCatalog,
        questVisible: () => true,
      ),
      generateId: () => 'synthetic:${++id}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'synthetic'),
      onAnswerCommitted: streak.afterAnswerCommitted,
    );
    for (final day in [_previousDay, _today]) {
      now = day;
      final session = await learning.startQuiz();
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: 'word',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
      );
    }
    final view = await progress.load();
    expect(view.streakDays, 2);
    final daily = view.quests!.current.singleWhere(
      (card) => card.cadence == QuestType.daily,
    );
    expect((daily.correctCount, daily.targetCount), (1, 5));
  }

  Future<void> switchOwner() async {
    final original = await owners.getOrCreateActiveOwner();
    await db.transaction(() async {
      await (db.update(db.localOwners)
            ..where((owner) => owner.id.equals(original.id)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await db
          .into(db.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'local:synthetic-replacement-owner',
              createdAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );
    });
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await _pumpUntil(tester, () async {
    if (target.evaluate().isNotEmpty) return true;
    final sheets = find.byType(BottomSheet);
    if (sheets.evaluate().isNotEmpty) {
      final scrollables = find.descendant(
        of: sheets.last,
        matching: find.byType(Scrollable),
      );
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.last, const Offset(0, -130));
      }
    }
    return false;
  }, label);
  await tester.ensureVisible(target.first);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _waitFor(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty, '$finder');

Future<void> _pumpUntil(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String description,
) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (await ready()) return;
  }
  fail('Timed out waiting for $description in the achievement share journey');
}

final class _Clock implements FocusClock {
  @override
  FocusSample sample() => FocusSample(
    utcMs: _today.millisecondsSinceEpoch,
    monotonicUs: 0,
    continuityId: 'synthetic-share-clock',
  );
}

final class _GuestSession extends Fake implements GuestSessionService {}
