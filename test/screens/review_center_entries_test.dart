import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/review_center_harness.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  for (final choose in [true, false]) {
    testWidgets(
      '${choose ? "P06" : "P08"} opens the real hub with the same owner and writers; retained ABA entry cannot navigate',
      (tester) async {
        late final Zone ioZone;
        final h = (await tester.runAsync(() {
          ioZone = Zone.current;
          return ReviewCenterHarness.open();
        }))!;
        StreamSubscription<String?>? observation;
        final observed = <String?>[];
        try {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.runAsync(() async {
            await h.save(configuredWordIds.first);
            await h.seedDue(configuredWordIds.first);
            await h.seedWrong();
          });
          final before = (await tester.runAsync(h.snapshotAllTables))!;
          expect(before, hasLength(37));
          final dependencies = AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _Guest(),
            database: h.database,
            localOwners: h.owners,
            progress: h.progress,
            reviewCenter: h.reviewCenter,
            learning: h.learning,
            savedWords: h.savedWords,
            wordReports: h.wordReports,
            fieldFeatures: const BuildFieldFeatureRegistry.allEnabled(),
          );
          observation = h.ownerChanges.listen(observed.add);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                locale: const Locale('en'),
                theme: M3Theme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
                home: choose
                    ? ChooseModeScreen(ownerChanges: h.ownerChanges)
                    : MasteryDashboardScreen(ownerChanges: h.ownerChanges),
              ),
            ),
          );
          await _until(tester, () => _entryAction(tester, choose) != null);
          final retained = _entryAction(tester, choose)!;
          observed.clear();
          await tester.runAsync(
            () => h.database.transaction(() async {
              await h.switchOwner(configuredOtherOwnerId);
              await h.switchOwner(configuredOwnerId);
            }),
          );
          await _until(
            tester,
            () =>
                observed.contains(null) &&
                observed.last == configuredOwnerId &&
                _entryAction(tester, choose) != null,
          );
          retained();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(ReviewCenterScreen), findsNothing);
          expect(await tester.runAsync(h.snapshotAllTables), before);

          final target = find
              .byKey(const ValueKey('review-center-entry'))
              .hitTestable();
          if (choose) {
            await tester.scrollUntilVisible(
              target,
              160,
              scrollable: find.byType(Scrollable).last,
            );
          }
          await tester.tap(target);
          await _until(
            tester,
            () =>
                find.byType(ReviewCenterScreen).evaluate().isNotEmpty &&
                find
                    .byKey(const ValueKey('review-center-count-saved'))
                    .evaluate()
                    .isNotEmpty,
          );
          final hub = tester.widget<ReviewCenterScreen>(
            find.byType(ReviewCenterScreen),
          );
          expect(hub.expectedOwnerId, configuredOwnerId);
          expect(hub.ownerChanges, same(h.ownerChanges));
          expect(hub.learning, same(h.learning));
          expect(hub.reviewCenter, same(h.reviewCenter));
          expect(hub.savedWords, same(h.savedWords));
          expect(hub.wordReports, same(h.wordReports));
          expect(hub.languageCode, 'en');
          expect(find.text('Review Center'), findsOneWidget);
          expect(await tester.runAsync(h.snapshotAllTables), before);
          await tester.tap(find.byType(BackButton).hitTestable());
          await _until(
            tester,
            () =>
                find.byType(ReviewCenterScreen).evaluate().isEmpty &&
                _entryAction(tester, choose) != null,
          );
          retained();
          await tester.pump();
          expect(find.byType(ReviewCenterScreen), findsNothing);
          expect(await tester.runAsync(h.snapshotAllTables), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(
            () =>
                ioZone.run(() => observation?.cancel() ?? Future<void>.value()),
          );
          await tester.runAsync(() => ioZone.run(h.close));
        }
      },
    );
  }
}

VoidCallback? _entryAction(WidgetTester tester, bool choose) {
  final entry = find.byKey(const ValueKey('review-center-entry'));
  if (entry.evaluate().isEmpty) return null;
  return choose
      ? tester
            .widget<ListTile>(
              find.descendant(of: entry, matching: find.byType(ListTile)),
            )
            .onTap
      : tester.widget<OutlinedButton>(entry).onPressed;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Synthetic Review Center entry did not reach its expected state');
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Entry reads cannot create a guest');
}
