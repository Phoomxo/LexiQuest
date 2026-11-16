import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  testWidgets('renders evidence-backed streak, skills, and sample sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ภาพรวมการเรียน'), findsOneWidget);
    expect(find.text('7 วัน'), findsOneWidget);
    expect(find.text('เรียนต่อเนื่อง'), findsOneWidget);
    expect(find.text('คะแนนประสบการณ์'), findsOneWidget);
    expect(find.text('รอบที่เรียนจบ'), findsOneWidget);
    expect(find.text('ระดับจากคะแนนประสบการณ์'), findsOneWidget);
    expect(find.text('ระดับการเรียน'), findsNothing);
    _expectMetric('ระดับจากคะแนนประสบการณ์', '${_snapshot.gameLevel}');
    _expectMetric('คะแนนประสบการณ์', '${_snapshot.totalXp}');
    _expectMetric('ความแม่นยำ', '80%');
    _expectMetric('เรียนต่อเนื่อง', '${_snapshot.streakDays} วัน');
    _expectMetric('รอบที่เรียนจบ', '${_snapshot.completedSessions}');
    _expectMetric('ถึงกำหนดทบทวน', '${_snapshot.dueReviewCount}');
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('คำนวณจาก 4 คำตอบ'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .semanticsLabel,
      'Listening แม่นยำ 75 เปอร์เซ็นต์',
    );
    await tester.scrollUntilVisible(
      find.text('คำนวณจาก 10 คำตอบที่บันทึกไว้'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('คำนวณจาก 10 คำตอบที่บันทึกไว้'), findsOneWidget);
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
  });

  testWidgets('empty evidence shows sample size zero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(loader: () async => _emptySnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
  });

  testWidgets('progress exposes weakness achievements and theme store', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('คำที่ควรฝึกเพิ่ม'), findsOneWidget);
    expect(find.text('ความสำเร็จ'), findsOneWidget);
    expect(find.text('ร้านค้ารางวัล'), findsOneWidget);

    await tester.tap(find.text('คำที่ควรฝึกเพิ่ม'));
    await tester.pumpAndSettle();
    expect(find.byType(WeaknessClinicScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(WeaknessClinicScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('ความสำเร็จ'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementsScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(AchievementsScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('ร้านค้ารางวัล'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopPage), findsOneWidget);
  });

  testWidgets(
    'Weakness return reloads the same Dashboard with fresh model data',
    (tester) async {
      var current = _snapshot;
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () async {
              loads++;
              return current;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final parent = tester.state(find.byType(MasteryDashboardScreen));
      expect(loads, 1);
      await _openWeakness(tester);
      expect(loads, 2); // The child legitimately reads its own snapshot.
      current = _xpSnapshot;
      await _popWeakness(tester);
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(tester.state(find.byType(MasteryDashboardScreen)), same(parent));
      _expectMetric('คะแนนประสบการณ์', '208');
      _expectMetric('ระดับจากคะแนนประสบการณ์', '11');
    },
  );

  for (final syncFailure in [false, true]) {
    testWidgets(
      'return refresh captures failure sync=$syncFailure without stale data',
      (tester) async {
        var loads = 0;
        Future<ProgressSnapshot> loader() {
          if (++loads <= 2) return Future.value(_snapshot);
          if (syncFailure) throw StateError('synthetic-private-detail');
          return Future.error(StateError('synthetic-private-detail'));
        }

        await tester.pumpWidget(
          MaterialApp(home: MasteryDashboardScreen(loader: loader)),
        );
        await tester.pumpAndSettle();
        await _openWeakness(tester);
        await _popWeakness(tester);
        await tester.pumpAndSettle();
        expect(loads, 3);
        expect(
          find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
          findsOneWidget,
        );
        expect(find.text('คะแนนประสบการณ์'), findsNothing);
        expect(find.textContaining('synthetic-private-detail'), findsNothing);
        expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'initial synchronous loader failure stays in the safe view error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () {
              throw StateError('synthetic-private-detail');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial loader failure retries once and recovers in place', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () {
            loads++;
            return loads == 1
                ? Future.error(StateError('synthetic-initial-error'))
                : Future.value(_snapshot);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
      findsOneWidget,
    );
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('คะแนนประสบการณ์'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending refresh hides a previous error until the current result',
    (tester) async {
      var loads = 0;
      final refresh = Completer<ProgressSnapshot>();
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () {
              return switch (++loads) {
                1 => Future.error(StateError('synthetic-initial-error')),
                2 => Future.value(_snapshot),
                _ => refresh.future,
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
        findsOneWidget,
      );
      await _openWeakness(tester);
      await _popWeakness(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
        findsNothing,
      );
      expect(find.text('คะแนนประสบการณ์'), findsNothing);
      refresh.complete(_xpSnapshot);
      await tester.pumpAndSettle();
      _expectMetric('คะแนนประสบการณ์', '208');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removed loader fails safely without reusing the old context', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () async {
            loads++;
            return _snapshot;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openWeakness(tester);
    await tester.pumpWidget(const MaterialApp(home: MasteryDashboardScreen()));
    await tester.pump();
    await _popWeakness(tester);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(
      find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
      findsOneWidget,
    );
    expect(find.text('คะแนนประสบการณ์'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'return refresh can replace evidence with the existing empty state',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () async {
              return ++loads <= 2 ? _snapshot : _emptySnapshot;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openWeakness(tester);
      await _popWeakness(tester);
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
      expect(find.text('คะแนนประสบการณ์'), findsNothing);
    },
  );

  testWidgets(
    'return uses the latest widget loader and ignores its superseded error',
    (tester) async {
      var oldLoads = 0;
      var newLoads = 0;
      final obsolete = Completer<ProgressSnapshot>();
      Future<ProgressSnapshot> oldLoader() async {
        oldLoads++;
        return _snapshot;
      }

      Future<ProgressSnapshot> newLoader() {
        return ++newLoads == 1 ? obsolete.future : Future.value(_xpSnapshot);
      }

      Widget app(ProgressLoader loader) =>
          MaterialApp(home: MasteryDashboardScreen(loader: loader));
      await tester.pumpWidget(app(oldLoader));
      await tester.pumpAndSettle();
      final parent = tester.state(find.byType(MasteryDashboardScreen));
      await _openWeakness(tester);
      await tester.pumpWidget(app(newLoader));
      await tester.pump();
      expect(newLoads, 1);
      await _popWeakness(tester);
      await tester.pumpAndSettle();
      expect(newLoads, 2);
      expect(oldLoads, 2);
      expect(tester.state(find.byType(MasteryDashboardScreen)), same(parent));
      _expectMetric('คะแนนประสบการณ์', '208');
      obsolete.completeError(StateError('synthetic-obsolete'));
      await tester.pumpAndSettle();
      _expectMetric('คะแนนประสบการณ์', '208');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('obsolete initial data cannot satisfy a pending return refresh', (
    tester,
  ) async {
    final initial = Completer<ProgressSnapshot>();
    final refresh = Completer<ProgressSnapshot>();
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () {
            return switch (++loads) {
              1 => initial.future,
              2 => Future.value(_snapshot),
              _ => refresh.future,
            };
          },
        ),
      ),
    );
    await tester.pump();
    await _openWeakness(tester);
    await _popWeakness(tester);
    expect(loads, 3);
    initial.complete(_snapshot);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('คะแนนประสบการณ์'), findsNothing);
    refresh.complete(_xpSnapshot);
    await tester.pumpAndSettle();
    _expectMetric('คะแนนประสบการณ์', '208');
  });

  testWidgets(
    'ordinary rebuild resize and non-Weakness returns do not reload',
    (tester) async {
      var loads = 0;
      Future<ProgressSnapshot> loader() async {
        loads++;
        return _snapshot;
      }

      Widget app(Brightness brightness) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MasteryDashboardScreen(loader: loader),
      );
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(Brightness.dark));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(loads, 1);
      await tester.tap(find.text('ความสำเร็จ'));
      await tester.pumpAndSettle();
      expect(loads, 2); // Achievements reads once, not a Dashboard refresh.
      Navigator.of(tester.element(find.byType(AchievementsScreen))).pop();
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.tap(find.text('ร้านค้ารางวัล'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ShopPage))).pop();
      await tester.pumpAndSettle();
      expect(loads, 2);
    },
  );

  testWidgets('hidden Weakness does not navigate or reload', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () async {
            loads++;
            return _snapshot;
          },
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.weakness: FieldFeatureState.hidden,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('คำที่ควรฝึกเพิ่ม'), findsNothing);
    expect(find.byType(WeaknessClinicScreen), findsNothing);
    expect(loads, 1);
  });

  testWidgets(
    'disposed parent does not reload when its Weakness route returns',
    (tester) async {
      var loads = 0;
      var show = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return show
                  ? MasteryDashboardScreen(
                      loader: () async {
                        loads++;
                        return _snapshot;
                      },
                    )
                  : const Text('removed');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openWeakness(tester);
      rebuild(() => show = false);
      await tester.pump();
      await _popWeakness(tester);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('removed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposed pending refresh ignores a late result', (tester) async {
    var loads = 0;
    final refresh = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () {
            return ++loads <= 2 ? Future.value(_snapshot) : refresh.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openWeakness(tester);
    await _popWeakness(tester);
    expect(loads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    refresh.complete(_xpSnapshot);
    await tester.pumpAndSettle();
    expect(loads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dependency replacement uses current progress and reads without writes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedProgress(db);
      final ownersA = _Owners('a');
      final ownersB = _Owners('b');
      AppDependencies dependencies(_Owners owners) => AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _NoGuest(),
        progress: ProgressUseCases(
          owners: owners,
          queries: DriftProgressQueries(db),
          nowUtc: () => DateTime.utc(2026, 10, 23),
        ),
      );
      Widget app(AppDependencies deps) => AppDependenciesScope(
        dependencies: deps,
        child: const MaterialApp(home: MasteryDashboardScreen()),
      );
      final before = await _databaseSnapshot(db);
      await tester.pumpWidget(app(dependencies(ownersA)));
      await _waitFor(
        tester,
        () =>
            ownersA.reads == 1 &&
            find.textContaining('คำนวณจาก 0 คำตอบ').evaluate().isNotEmpty,
      );
      await _openWeakness(tester);
      expect(ownersA.reads, 2);
      await tester.pumpWidget(app(dependencies(ownersB)));
      await _waitFor(tester, () => ownersB.reads >= 1);
      await _popWeakness(tester);
      await _waitFor(
        tester,
        () => find.text('คะแนนประสบการณ์').evaluate().isNotEmpty,
      );
      expect(ownersA.reads, 2);
      expect(ownersB.reads, 2);
      _expectMetric('คะแนนประสบการณ์', '1');
      expect(await _databaseSnapshot(db), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final brightness in Brightness.values) {
      testWidgets('XP label is readable at 2x $size $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        var loads = 0;
        final refresh = Completer<ProgressSnapshot>();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light
                  ? M3Theme.lightTheme
                  : M3Theme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: MasteryDashboardScreen(
                loader: () {
                  loads++;
                  if (loads == 3) return refresh.future;
                  return Future.value(loads >= 5 ? _snapshot : _xpSnapshot);
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final dashboardContext = tester.element(
            find.byType(MasteryDashboardScreen),
          );
          expect(MediaQuery.sizeOf(dashboardContext), size);
          expect(MediaQuery.textScalerOf(dashboardContext).scale(14), 28);
          expect(Theme.of(dashboardContext).brightness, brightness);
          expect(tester.takeException(), isNull);
          final title = find.text('ภาพรวมการเรียน');
          expect(
            tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
            isFalse,
          );
          expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);

          final label = find.text('ระดับจากคะแนนประสบการณ์');
          expect(label, findsOneWidget);
          await tester.scrollUntilVisible(label, 100);
          await tester.pumpAndSettle();
          expect(label.hitTestable(), findsOneWidget);
          expect(find.text('ระดับการเรียน'), findsNothing);
          _expectMetric('ระดับจากคะแนนประสบการณ์', '${_xpSnapshot.gameLevel}');
          _expectMetric('คะแนนประสบการณ์', '${_xpSnapshot.totalXp}');
          _expectMetric('ความแม่นยำ', '80%');
          _expectMetric('เรียนต่อเนื่อง', '7 วัน');
          final labelRect = tester.getRect(label);
          final viewport = tester.getRect(find.byType(ListView));
          expect(labelRect.left, greaterThanOrEqualTo(viewport.left));
          expect(labelRect.right, lessThanOrEqualTo(viewport.right));
          expect(labelRect.top, greaterThanOrEqualTo(viewport.top));
          expect(labelRect.bottom, lessThanOrEqualTo(viewport.bottom));
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.text.toPlainText(), 'ระดับจากคะแนนประสบการณ์');
          expect(
            tester.getSemantics(label).getSemanticsData().label,
            contains('ระดับจากคะแนนประสบการณ์'),
          );
          expect(find.bySemanticsLabel(RegExp('ระดับการเรียน')), findsNothing);
          expect(loads, 1);
          expect(tester.takeException(), isNull);
          final weaknessAction = find.widgetWithText(
            OutlinedButton,
            'คำที่ควรฝึกเพิ่ม',
          );
          expect(
            tester.getSize(weaknessAction).height,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester.getSize(weaknessAction).width,
            greaterThanOrEqualTo(48),
          );
          await _openWeakness(tester);
          await _popWeakness(tester);
          expect(loads, 3);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            tester
                .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator),
                )
                .semanticsLabel,
            'กำลังอ่านประวัติการเรียน',
          );
          expect(find.text('คะแนนประสบการณ์'), findsNothing);
          refresh.completeError(StateError('synthetic-refresh-failure'));
          await tester.pumpAndSettle();
          expect(
            find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('คะแนนประสบการณ์'), findsNothing);
          expect(tester.takeException(), isNull);
          await _openWeakness(tester);
          await _popWeakness(tester);
          await tester.pumpAndSettle();
          expect(loads, 5);
          await tester.scrollUntilVisible(label, 100);
          await tester.pumpAndSettle();
          expect(label.hitTestable(), findsOneWidget);
          _expectMetric('คะแนนประสบการณ์', '8');
          _expectMetric('ระดับจากคะแนนประสบการณ์', '1');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}

void _expectMetric(String label, String value) {
  final card = find.ancestor(of: find.text(label), matching: find.byType(Card));
  expect(find.descendant(of: card, matching: find.text(value)), findsOneWidget);
}

const _snapshot = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: 0.8,
  totalXp: 8,
  completedSessions: 2,
  streakDays: 7,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 1,
  skills: [
    SkillEvidence(
      key: 'listening',
      label: 'Listening',
      sampleSize: 4,
      accuracy: 0.75,
    ),
  ],
  weaknesses: [],
  recommendations: [],
);

const _emptySnapshot = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final _xpSnapshot = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: 0.8,
  totalXp: 208,
  completedSessions: 2,
  streakDays: 7,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 11,
  skills: _snapshot.skills,
  weaknesses: [],
  recommendations: [],
);

Future<void> _openWeakness(WidgetTester tester) async {
  await tester.tap(find.text('คำที่ควรฝึกเพิ่ม'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _waitFor(
    tester,
    () =>
        find.byType(WeaknessClinicScreen).evaluate().isNotEmpty &&
        find
            .descendant(
              of: find.byType(WeaknessClinicScreen),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isEmpty,
  );
}

Future<void> _popWeakness(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(WeaknessClinicScreen))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Timed out waiting for synthetic progress');
}

final class _Owners implements LocalOwnerRepository {
  _Owners(this.id);
  final String id;
  int reads = 0;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    reads++;
    return LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 10, 23));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

Future<void> _seedProgress(AppDatabase db) async {
  for (final owner in ['a', 'b']) {
    await db
        .into(db.localOwners)
        .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
  }
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'synthetic-category',
          ownerId: 'b',
          name: 'Synthetic',
          normalizedName: 'synthetic',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'synthetic-word',
          ownerId: 'b',
          categoryId: 'synthetic-category',
          spelling: 'synthetic',
          normalizedSpelling: 'synthetic',
          meaning: 'สังเคราะห์',
          normalizedMeaning: 'สังเคราะห์',
          partOfSpeech: 'adjective',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final learning = DriftLearningRepository(db);
  final now = DateTime.utc(2026, 10, 23);
  await learning.startSession(
    LearningSessionDraft(
      id: 'synthetic-session',
      ownerId: 'b',
      activityType: 'quiz',
      startedAtUtc: now,
      appVersion: 'test',
      buildId: 'test',
    ),
  );
  await learning.recordAnswer(
    RecordAnswerCommand(
      id: 'synthetic-attempt',
      ownerId: 'b',
      sessionId: 'synthetic-session',
      wordId: 'synthetic-word',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 500,
      attemptNumber: 1,
      occurredAtUtc: now,
    ),
  );
}

Future<Map<String, List<String>>> _databaseSnapshot(AppDatabase db) async => {
  for (final table in db.allTables)
    table.actualTableName:
        (await db
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
};
