import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

import '../../integration_test/support/native_baseline_cases.dart';
import '../../integration_test/support/native_baseline_fixture.dart';
import 'composed_host_ui_audit_test.dart' show composeHost, settleHost, tapHost;

const _output = 'docs/development/ux-delivery/evidence/S01-BQ-runs';

// HOST SYNTHETIC ONLY. Direct inserts are disposable test inputs, never an
// earning/scoring authority or learner evidence. All displayed calculations use
// existing production readers. No SRS, rewards, research or outbox seed writes.
Future<void> _seedLearning(NativeBaselineFixture fixture) async {
  final db = fixture.database;
  final owner = await fixture.owners.getOrCreateActiveOwner();
  final word = (await db.select(db.vocabularyWords).get()).single;
  final start = DateTime.utc(2026, 9, 26, 3);
  final evidence = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'retention',
    hintLevel: 0,
    contentRevision: 'synthetic-bq-v1',
    engagementAllowed: false,
  );
  for (var i = 0; i < 2; i++) {
    final session = 'synthetic-bq-session-$i';
    await db
        .into(db.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: session,
            ownerId: owner.id,
            activityType: 'quiz',
            state: 'completed',
            startedAtUtcMs: start.millisecondsSinceEpoch,
            appVersion: 'synthetic-host-only',
            buildId: 'synthetic-bq',
          ),
        );
    await db
        .into(db.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'synthetic-bq-answer-$i',
            ownerId: owner.id,
            sessionId: session,
            wordId: word.id,
            promptMode: 'meaningChoice',
            isCorrect: i == 0,
            attemptNumber: 1,
            occurredAtUtcMs: start
                .add(Duration(minutes: i))
                .millisecondsSinceEpoch,
            evidenceClass: Value(evidence.evidenceClass.name),
            evidenceContextJson: Value(jsonEncode(evidence.toJson())),
          ),
        );
  }
  await db
      .into(db.learningTimeSegments)
      .insert(
        LearningTimeSegmentsCompanion.insert(
          id: 'synthetic-bq-active79',
          ownerId: owner.id,
          sessionId: 'synthetic-bq-session-0',
          activeStartOffsetMs: 0,
          activeDurationMs: 79000,
          startedAtUtcMs: start.millisecondsSinceEpoch,
          endedAtUtcMs: start
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          timezoneId: 'Asia/Bangkok',
          timezoneOffsetMinutes: 420,
          captureSource: 'automaticLesson',
        ),
      );
}

Future<Map<String, Object?>> _rows(AppDatabase db) async {
  final result = <String, Object?>{};
  final names = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  for (final row in names) {
    final name = row.read<String>('name');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) throw StateError(name);
    result[name] =
        (await db.customSelect('SELECT * FROM $name ORDER BY 1').get())
            .map((r) => r.data)
            .toList();
  }
  return result;
}

Future<void> _capture(WidgetTester tester, String name) async {
  await settleHost(tester);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('bq-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('$_output/host-renders/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _keyboard(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  bool focused() {
    final element = target.evaluate().single;
    var found = FocusManager.instance.primaryFocus?.context == element;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      ancestor,
    ) {
      found |= ancestor == element;
      return !found;
    });
    return found;
  }

  for (var i = 0; i < 20 && !focused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settleHost(tester);
  }
  expect(focused(), isTrue, reason: 'Action reachable by host Tab');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await settleHost(tester);
}

void main() {
  setUpAll(() async {
    timezone_data.initializeTimeZones();
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'BQ populated profile host ${scale}x',
      (tester) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final fixture = (await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp(
            'bq-host-synthetic-',
          );
          final f = await NativeBaselineFixture.open(
            root,
            'bm-bq-host',
            seed: true,
          );
          await f.seed();
          await f.changePreferenceAndCreateWord(changeDisplay: false);
          final before = await _rows(f.database);
          await _seedLearning(f);
          final seeded = await _rows(f.database);
          final changed = before.keys
              .where((k) => jsonEncode(before[k]) != jsonEncode(seeded[k]))
              .toSet();
          expect(changed, {
            'learning_sessions',
            'answer_attempts',
            'learning_time_segments',
          });
          return f;
        }))!;
        final deps = composeHost(fixture);
        final semantics = tester.ensureSemantics();
        final network = HttpOverrides.current;
        HttpOverrides.global = fixture.network;
        try {
          final before = await baselineAwait(
            tester,
            () => _rows(fixture.database),
          );
          final profile = await baselineAwait(
            tester,
            deps.progress!.loadPersonalLearningProfile,
          );
          expect(profile.isEmpty, isFalse);
          expect(profile.mastery.masteredWordCount, 0);
          expect(
            profile.mastery.availability,
            ProfileAxisAvailability.available,
          );
          expect(profile.srs.availability, ProfileAxisAvailability.noEvidence);
          expect(profile.accuracy.sampleSize, 2);
          expect(profile.accuracy.correctCount, 1);
          expect(profile.accuracy.value, 0.5);
          expect(profile.effort.activeDuration, const Duration(seconds: 79));
          expect(profile.engagement.completedSessionCount, 2);
          expect(profile.engagement.totalXp, 0);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('bq-capture'),
              child: MyApp(dependencies: deps, ownsDependencies: false),
            ),
          );
          await settleHost(tester);
          expect(deps.features.isVisible(Feature.dailyContinuity), isFalse);
          await tapHost(tester, 'home/profile');
          expect(
            find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
            findsNothing,
          );
          expect(find.text('0 คำที่ชำนาญ'), findsOneWidget);
          await _capture(tester, '01-profile-${scale}x');
          await tester.ensureVisible(find.text('1 นาที 19 วินาที'));
          await _capture(tester, '02-effort-${scale}x');
          await _keyboard(
            tester,
            find.byKey(const ValueKey('profile-learning-details')),
          );
          await tester.ensureVisible(find.text('50% จาก 2 คำตอบ'));
          expect(
            tester
                .getSemantics(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.value == '50% จาก 2 คำตอบ',
                  ),
                )
                .getSemanticsData()
                .value,
            '50% จาก 2 คำตอบ',
          );
          await _capture(tester, '03-accuracy-${scale}x');
          await tester.ensureVisible(find.text('0 XP · ต่อเนื่อง 0 วัน'));
          await _capture(tester, '04-details-${scale}x');
          await _keyboard(
            tester,
            find.byKey(const ValueKey('profile-open-mastery')),
          );
          expect(find.text('ภาพรวมการเรียน'), findsOneWidget);
          await _capture(tester, '05-overview-${scale}x');
          final list = find.byType(Scrollable).first;
          for (var i = 0; i < 12; i++) {
            await tester.drag(list, const Offset(0, -500));
            await _capture(tester, '06-overview-$i-${scale}x');
            final position = tester.state<ScrollableState>(list).position;
            if (position.pixels >= position.maxScrollExtent) break;
          }
          final position = tester.state<ScrollableState>(list).position;
          expect(
            position.pixels,
            position.maxScrollExtent,
            reason: 'Inspect the full overview through its final actions',
          );
          await _keyboard(tester, find.byType(BackButton));
          expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
          expect(
            await baselineAwait(tester, () => _rows(fixture.database)),
            before,
            reason:
                'All application tables unchanged by readers and navigation',
          );
          expect(fixture.network.calls, 0);
          expect(fixture.gatewayCalls, 0);
          await tester.runAsync(
            () => File('$_output/isolation-${scale}x.json').writeAsString(
              jsonEncode({
                'syntheticOnly': true,
                'tablesUnchanged': before.length,
                'seedChangedOnly': [
                  'learning_sessions',
                  'answer_attempts',
                  'learning_time_segments',
                ],
                'httpCalls': fixture.network.calls,
                'gatewayCalls': fixture.gatewayCalls,
                'accuracy': 0.5,
                'sampleSize': 2,
                'activeSeconds': 79,
                'native': 'NOT_RUN',
              }),
            ),
          );
        } finally {
          HttpOverrides.global = network;
          debugDisableShadows = shadows;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          semantics.dispose();
          (deps.features as RuntimeFeatureRegistry).dispose();
          deps.quest.dispose();
          await baselineAwait(tester, fixture.close);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
