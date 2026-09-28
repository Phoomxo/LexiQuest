import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  for (final result in ['true', 'false', 'error']) {
    testWidgets('BH cancel $result catalog failure recovers with bounded retry',
        (tester) async {
      final manager = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      var allowed = true;
      await tester.pumpWidget(MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => allowed,
        ),
      ));
      await tester.pumpAndSettle();
      final cancel = tester.widget<TextButton>(find.byKey(
        const ValueKey('offline-content/cancel/pack-a'),
      )).onPressed!;
      cancel();
      await tester.pumpAndSettle();
      manager.catalogFailures = 1;
      if (result == 'error') {
        manager.cancelPending!.completeError(StateError('synthetic cancel'));
      } else {
        manager.cancelPending!.complete(result == 'true');
      }
      await tester.pumpAndSettle();
      expect(manager.catalogCalls, 2);
      expect(find.text('อ่านสถานะเนื้อหาออฟไลน์ไม่ได้'), findsOneWidget);
      expect(find.textContaining('private failure'), findsNothing);
      final retry = tester.widget<FilledButton>(find.byKey(
        const ValueKey('offline-content/retry'),
      )).onPressed!;
      allowed = false;
      retry();
      expect(manager.catalogCalls, 2);
      allowed = true;
      manager.catalogPending = Completer<List<OfflineContentState>>();
      retry();
      retry();
      cancel();
      await tester.pump();
      expect(manager.catalogCalls, 3);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(manager.cancelled, [_identity]);
      manager.catalogPending!.complete([_state(OfflineContentStatus.interrupted)]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('offline-content/repair/pack-a')),
          findsOneWidget);
      retry();
      cancel();
      await tester.pumpAndSettle();
      expect(manager.catalogCalls, 3);
      expect(manager.cancelled, [_identity]);
      expect(manager.downloaded, isEmpty);
      expect(manager.repaired, isEmpty);
      expect(manager.removed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('BH cancel catalog late completion fences owner fail=$fail',
        (tester) async {
      final old = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      final next = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      Widget screen(_FakeManager manager) => MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      );
      final cancel = find.byKey(const ValueKey('offline-content/cancel/pack-a'));
      await tester.pumpWidget(screen(old));
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      old.catalogPending = Completer<List<OfflineContentState>>();
      old.cancelPending!.complete(true);
      await tester.pump();
      await tester.pump();
      expect(old.catalogCalls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final oldMetadataReads = old.metadataReads.length;
      await tester.pumpWidget(screen(next));
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      final nextMetadataReads = next.metadataReads.length;
      if (fail) {
        old.catalogPending!.completeError(StateError('synthetic old catalog'));
      } else {
        old.catalogPending!.complete([_state(OfflineContentStatus.verified)]);
      }
      await tester.pumpAndSettle();
      expect(old.metadataReads.length, oldMetadataReads);
      expect(next.metadataReads.length, nextMetadataReads);
      expect(next.catalogCalls, 1);
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      expect(find.byKey(const ValueKey('offline-content/retry')), findsNothing);
      expect(find.byKey(const ValueKey('offline-content/remove/pack-a')), findsNothing);
      next.values[0] = _state(OfflineContentStatus.interrupted);
      next.cancelPending!.complete(true);
      await tester.pumpAndSettle();
      expect(next.catalogCalls, 2);
      expect(find.byKey(const ValueKey('offline-content/repair/pack-a')),
          findsOneWidget);
      expect(old.cancelled, [_identity]);
      expect(next.cancelled, [_identity]);
      expect(old.downloaded, isEmpty);
      expect(next.downloaded, isEmpty);
      expect(old.repaired, isEmpty);
      expect(next.repaired, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BH failed cancel catalog retry retires across owner replacement',
      (tester) async {
    final old = _FakeManager([_state(OfflineContentStatus.downloading)])
      ..cancelPending = Completer<bool>();
    final next = _FakeManager([])
      ..catalogPending = Completer<List<OfflineContentState>>();
    Widget screen(_FakeManager manager) => MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    );
    await tester.pumpWidget(screen(old));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-content/cancel/pack-a')));
    await tester.pumpAndSettle();
    old.catalogFailures = 1;
    old.cancelPending!.complete(true);
    await tester.pumpAndSettle();
    final retry = tester.widget<FilledButton>(find.byKey(
      const ValueKey('offline-content/retry'),
    )).onPressed!;
    await tester.pumpWidget(screen(next));
    retry();
    await tester.pump();
    expect(old.catalogCalls, 2);
    expect(next.catalogCalls, 1);
    next.catalogPending!.complete([]);
    await tester.pumpAndSettle();
    retry();
    await tester.pumpAndSettle();
    expect(next.catalogCalls, 1);
    expect(find.text('ยังไม่มีแพ็กเนื้อหาที่รองรับการใช้งานออฟไลน์'), findsOneWidget);
    expect(next.cancelled, isEmpty);
    expect(next.downloaded, isEmpty);
    expect(next.repaired, isEmpty);
    expect(next.removed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final result in ['true', 'false', 'error']) {
    testWidgets('BG external cancel refreshes actual catalog after $result',
        (tester) async {
      final manager = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      await tester.pumpWidget(MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ));
      await tester.pumpAndSettle();
      final cancel = find.byKey(const ValueKey('offline-content/cancel/pack-a'));
      final stale = tester.widget<TextButton>(cancel).onPressed!;
      stale();
      stale();
      await tester.pumpAndSettle();
      expect(manager.cancelled, [_identity]);
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      // The external operation publishes its real state before cancel resolves.
      manager.values[0] = _state(result == 'false'
          ? OfflineContentStatus.verified
          : OfflineContentStatus.interrupted);
      if (result == 'error') {
        manager.cancelPending!.completeError(StateError('synthetic cancel'));
      } else {
        manager.cancelPending!.complete(result == 'true');
      }
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('offline-content/${result == 'false' ? 'remove' : 'repair'}/pack-a')),
          findsOneWidget);
      expect(cancel, findsNothing);
      expect(manager.catalogCalls, 2);
      stale();
      await tester.pumpAndSettle();
      expect(manager.cancelled, [_identity]);
      expect(manager.downloaded, isEmpty);
      expect(manager.repaired, isEmpty);
      if (result != 'true') {
        expect(find.text(result == 'false'
            ? 'ไม่มีการดาวน์โหลดที่ยกเลิกได้แล้ว'
            : 'ยกเลิกไม่สำเร็จ ลองใหม่ได้'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in ['owner', 'gate', 'app', 'route', 'disposed']) {
    testWidgets('BG pending external cancel respects $boundary boundary',
        (tester) async {
      final old = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      final next = _FakeManager([]);
      var allowed = true;
      final navigator = GlobalKey<NavigatorState>();
      Widget screen(_FakeManager manager) => MaterialApp(
        navigatorKey: navigator,
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => allowed,
        ),
      );
      await tester.pumpWidget(screen(old));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('offline-content/cancel/pack-a')));
      await tester.pumpAndSettle();
      if (boundary == 'owner') {
        await tester.pumpWidget(screen(next));
      } else if (boundary == 'gate') {
        allowed = false;
      } else if (boundary == 'app') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (boundary == 'route') {
        navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ));
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      old.values[0] = _state(OfflineContentStatus.interrupted);
      old.cancelPending!.complete(true);
      await tester.pumpAndSettle();
      expect(old.catalogCalls, 1);
      expect(old.cancelled, [_identity]);
      expect(next.cancelled, isEmpty);
      if (boundary == 'owner') expect(next.catalogCalls, 1);
      if (boundary == 'app' || boundary == 'route' || boundary == 'gate') {
        allowed = true;
        if (boundary == 'route') {
          navigator.currentState!.pop();
        } else {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('offline-content/repair/pack-a')),
            findsOneWidget);
        expect(old.catalogCalls, 2);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BF unrelated catalog refresh preserves current failure feedback',
      (tester) async {
    const other = ContentIdentity(
      type: ContentType.offlineArtifact,
      id: 'pack-b',
      revision: 1,
    );
    final manager = _FakeManager([
      _state(OfflineContentStatus.interrupted),
      _state(OfflineContentStatus.notDownloaded, identity: other),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-content/repair/pack-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-content/download/pack-b')));
    await tester.pumpAndSettle();
    expect(manager.catalogCalls, 2);
    expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
    manager.repairCompleter.completeError(StateError('synthetic repair'));
    await tester.pumpAndSettle();
    expect(find.text('จัดการเนื้อหาออฟไลน์ไม่สำเร็จ ลองใหม่ได้'), findsOneWidget);
    expect(manager.repaired, [_identity]);
    expect(manager.downloaded, [other]);
    expect(tester.takeException(), isNull);
  });

  for (final transition in ['none', 'app', 'route']) {
    for (final result in ['repair-error', 'cancel-error', 'cancel-false']) {
      testWidgets('BF pending $result feedback after $transition', (tester) async {
        final repair = result == 'repair-error';
        final manager = _FakeManager([
          _state(repair
              ? OfflineContentStatus.interrupted
              : OfflineContentStatus.downloading),
        ])..cancelPending = Completer<bool>();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ));
        await tester.pumpAndSettle();
        final action = find.byKey(ValueKey(
          'offline-content/${repair ? 'repair' : 'cancel'}/pack-a',
        ));
        await tester.tap(action);
        await tester.pumpAndSettle();
        await _feedbackVisibilityTransition(tester, navigator, transition);
        // Returning must not abandon the manager operation or admit a duplicate.
        if (repair) {
          expect(action, findsNothing);
          expect(manager.repaired, [_identity]);
          manager.repairCompleter.completeError(StateError('synthetic repair'));
        } else {
          expect(tester.widget<TextButton>(action).onPressed, isNull);
          expect(manager.cancelled, [_identity]);
          if (result == 'cancel-error') {
            manager.cancelPending!.completeError(StateError('synthetic cancel'));
          } else {
            manager.cancelPending!.complete(false);
          }
        }
        await tester.pumpAndSettle();
        final message = repair
            ? 'จัดการเนื้อหาออฟไลน์ไม่สำเร็จ ลองใหม่ได้'
            : result == 'cancel-error'
                ? 'ยกเลิกไม่สำเร็จ ลองใหม่ได้'
                : 'ไม่มีการดาวน์โหลดที่ยกเลิกได้แล้ว';
        expect(find.text(message),
            transition == 'none' ? findsOneWidget : findsNothing);
        expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsNothing);
        if (repair) {
          expect(action, findsOneWidget);
          expect(manager.repaired, [_identity]);
        } else {
          expect(tester.widget<TextButton>(action).onPressed, isNotNull);
          expect(manager.cancelled, [_identity]);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final transition in ['app', 'route']) {
    testWidgets('BF pending repair success remains truthful after $transition',
        (tester) async {
      final manager = _FakeManager([_state(OfflineContentStatus.interrupted)]);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ));
      await tester.pumpAndSettle();
      final repair = find.byKey(const ValueKey('offline-content/repair/pack-a'));
      final retired = tester.widget<FilledButton>(repair).onPressed!;
      await tester.tap(repair);
      await tester.pumpAndSettle();
      await _feedbackVisibilityTransition(tester, navigator, transition);
      retired();
      await tester.pumpAndSettle();
      expect(manager.repaired, [_identity]);
      expect(manager.cancelled, isEmpty);
      expect(repair, findsNothing);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsNothing);
      manager.repairCompleter.complete(_state(OfflineContentStatus.verified));
      await tester.pumpAndSettle();
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
      expect(find.byKey(const ValueKey('offline-content/remove/pack-a')),
          findsOneWidget);
      expect(manager.repaired, [_identity]);
      expect(manager.cancelled, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final routeCover in [false, true]) {
    testWidgets(
      'BE retired remove stays retired after return route=$routeCover',
      (tester) async {
        final manager = _FakeManager([_state(OfflineContentStatus.verified)]);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: OfflineContentManagerScreen(
              manager: manager,
              canInvoke: () => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final remove = find.byKey(
          const ValueKey('offline-content/remove/pack-a'),
        );
        final retired = tester.widget<OutlinedButton>(remove).onPressed!;
        if (routeCover) {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
          navigator.currentState!.pop();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpAndSettle();
        retired();
        await tester.pumpAndSettle();
        expect(manager.removed, isEmpty);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(manager.removed, [_identity]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('BE background callback cannot mutate', (tester) async {
    final manager = _FakeManager([_state(OfflineContentStatus.verified)]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retired = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('offline-content/remove/pack-a')),
        )
        .onPressed!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    retired();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.removed, isEmpty);
  });

  for (final repair in [false, true]) {
    testWidgets('BE transfer callback retires on resume repair=$repair', (
      tester,
    ) async {
      final manager = _FakeManager([
        _state(
          repair
              ? OfflineContentStatus.interrupted
              : OfflineContentStatus.notDownloaded,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(
        ValueKey('offline-content/${repair ? 'repair' : 'download'}/pack-a'),
      );
      final retired = tester.widget<FilledButton>(action).onPressed!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      retired();
      await tester.pumpAndSettle();
      expect(manager.downloaded, isEmpty);
      expect(manager.repaired, isEmpty);
      await tester.tap(action);
      if (repair) {
        manager.repairCompleter.complete(_state(OfflineContentStatus.verified));
      }
      await tester.pumpAndSettle();
      expect(repair ? manager.repaired : manager.downloaded, [_identity]);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
    });
  }

  testWidgets('BE ongoing download survives resume with fresh cancellation', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.notDownloaded)])
      ..waitDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pumpAndSettle();
    final cancel = find.byKey(const ValueKey('offline-content/cancel/pack-a'));
    final retired = tester.widget<TextButton>(cancel).onPressed!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    retired();
    await tester.pumpAndSettle();
    expect(manager.cancelled, isEmpty);
    expect(manager.downloaded, [_identity]);
    expect(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
      findsNothing,
    );
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(manager.cancelled, [_identity]);
    expect(
      find.byKey(const ValueKey('offline-content/repair/pack-a')),
      findsOneWidget,
    );
  });

  testWidgets('BE resume refresh failure retires retry and needs fresh retry', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.notDownloaded)])
      ..catalogFailures = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('offline-content/retry'));
    final retired = tester.widget<FilledButton>(retry).onPressed!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.catalogCalls, 2);
    retired();
    await tester.pumpAndSettle();
    expect(manager.catalogCalls, 2);
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(manager.catalogCalls, 3);
    expect(manager.downloaded, isEmpty);
    expect(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
      findsOneWidget,
    );
  });

  testWidgets('BE pending catalog after resume fences old and fresh actions', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.verified)]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retired = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('offline-content/remove/pack-a')),
        )
        .onPressed!;
    manager.catalogPending = Completer<List<OfflineContentState>>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    retired();
    await tester.pump();
    expect(manager.removed, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    manager.catalogPending!.complete([
      _state(OfflineContentStatus.notDownloaded),
    ]);
    await tester.pumpAndSettle();
    retired();
    await tester.pumpAndSettle();
    expect(manager.removed, isEmpty);
    expect(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
      findsOneWidget,
    );
  });

  testWidgets(
    'BD failed refresh retires actions until explicit read recovery',
    (tester) async {
      final manager = _FakeManager([_state(OfflineContentStatus.verified)]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retiredRemove = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('offline-content/remove/pack-a')),
          )
          .onPressed!;
      manager.catalogFailures = 1;
      retiredRemove();
      await tester.pumpAndSettle();
      expect(find.text('อ่านสถานะเนื้อหาออฟไลน์ไม่ได้'), findsOneWidget);
      retiredRemove();
      await tester.pumpAndSettle();
      expect(manager.removed, [_identity]);
      expect(manager.catalogCalls, 2);
      await tester.tap(find.byKey(const ValueKey('offline-content/retry')));
      await tester.pumpAndSettle();
      expect(manager.catalogCalls, 3);
      expect(manager.downloaded, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('offline-content/download/pack-a')),
      );
      await tester.pumpAndSettle();
      expect(manager.downloaded, [_identity]);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('BD refreshed cancel still controls its ongoing download', (
    tester,
  ) async {
    const second = ContentIdentity(
      type: ContentType.learningPack,
      id: 'pack-b',
      revision: 1,
    );
    final manager = _FakeManager([
      _state(OfflineContentStatus.notDownloaded),
      _state(OfflineContentStatus.verified, identity: second),
    ])..waitDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pump();
    final retiredCancel = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('offline-content/cancel/pack-a')),
        )
        .onPressed!;
    await tester.tap(
      find.byKey(const ValueKey('offline-content/remove/pack-b')),
    );
    await tester.pump();
    await tester.pump();
    retiredCancel();
    await tester.pump();
    expect(manager.cancelled, isEmpty);
    expect(manager.removed, [second]);
    expect(manager.values.map((state) => state.identity), [_identity, second]);
    await tester.tap(
      find.byKey(const ValueKey('offline-content/cancel/pack-a')),
    );
    await tester.pumpAndSettle();
    expect(manager.downloaded, [_identity]);
    expect(manager.cancelled, [_identity]);
    expect(find.text('การดาวน์โหลดถูกขัดจังหวะ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final repair in [false, true]) {
    testWidgets(
      'BD retired transfer cannot restart after removal repair=$repair',
      (tester) async {
        final manager = _FakeManager([
          _state(
            repair
                ? OfflineContentStatus.quarantined
                : OfflineContentStatus.notDownloaded,
          ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: OfflineContentManagerScreen(
              manager: manager,
              canInvoke: () => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retiredTransfer = tester
            .widget<FilledButton>(
              find.byKey(
                ValueKey(
                  'offline-content/${repair ? 'repair' : 'download'}/pack-a',
                ),
              ),
            )
            .onPressed!;
        retiredTransfer();
        if (repair) {
          manager.repairCompleter.complete(
            _state(OfflineContentStatus.verified),
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('offline-content/remove/pack-a')),
        );
        await tester.pumpAndSettle();
        retiredTransfer();
        await tester.pumpAndSettle();
        expect(repair ? manager.repaired : manager.downloaded, [_identity]);
        expect(
          manager.values.single.status,
          OfflineContentStatus.notDownloaded,
        );
        expect(find.text('ยังไม่ได้ดาวน์โหลด'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
        );
        await tester.pumpAndSettle();
        expect(manager.values.single.status, OfflineContentStatus.verified);
        expect(manager.downloaded.length, repair ? 1 : 2);
      },
    );
  }

  testWidgets('BD retired cancel cannot cancel a later repair', (tester) async {
    final manager = _FakeManager([_state(OfflineContentStatus.notDownloaded)])
      ..waitDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pump();
    final retiredCancel = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('offline-content/cancel/pack-a')),
        )
        .onPressed!;
    retiredCancel();
    await tester.pumpAndSettle();
    expect(find.text('การดาวน์โหลดถูกขัดจังหวะ'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('offline-content/repair/pack-a')),
    );
    await tester.pump();
    manager.cancelPending = Completer<bool>();
    retiredCancel();
    await tester.pump();
    expect(manager.cancelled, [_identity]);
    await tester.tap(
      find.byKey(const ValueKey('offline-content/cancel/pack-a')),
    );
    await tester.pump();
    expect(manager.cancelled, [_identity, _identity]);
    manager.cancelPending!.complete(true);
    manager.repairCompleter.complete(_state(OfflineContentStatus.interrupted));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('BD retired remove cannot delete a fresh installation', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.verified)]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retiredRemove = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('offline-content/remove/pack-a')),
        )
        .onPressed!;
    retiredRemove();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pumpAndSettle();
    expect(manager.downloaded, [_identity]);
    expect(manager.values.single.status, OfflineContentStatus.verified);

    retiredRemove();
    await tester.pumpAndSettle();
    expect(manager.removed, [_identity]);
    expect(manager.values.single.status, OfflineContentStatus.verified);
    expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('offline-content/remove/pack-a')),
    );
    await tester.pumpAndSettle();
    expect(manager.removed, [_identity, _identity]);
    expect(manager.values.single.status, OfflineContentStatus.notDownloaded);
  });

  testWidgets(
    'AC dependency replacement refreshes pinned title with same manager',
    (tester) async {
      const identity = ContentIdentity(
        type: ContentType.learningPack,
        id: 'pack-a',
        revision: 1,
      );
      final manager = _FakeManager([
        _state(OfflineContentStatus.verified, identity: identity),
      ]);
      LearningPackSummary pack(String title) => LearningPackSummary(
        packId: 'pack-a',
        revision: 1,
        title: title,
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'recognition',
        goal: 'practice',
        contentIdentity: identity,
      );
      final pending = Completer<LearningPackDetail>();
      await tester.pumpWidget(
        _withPackMetadata(manager, pack('old title'), pending: pending),
      );
      await tester.pump();
      await tester.pumpWidget(
        _withPackMetadata(manager, pack('current title')),
      );
      await tester.pumpAndSettle();
      expect(find.text('current title'), findsOneWidget);
      pending.complete(
        LearningPackDetail(
          summary: pack('old title'),
          vocabularyWordIds: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('current title'), findsOneWidget);
      expect(find.text('old title'), findsNothing);
      expect(manager.catalogCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AC retry recovers pinned catalog without mutations or stale retry',
    (tester) async {
      final manager = _FakeManager([_state(OfflineContentStatus.verified)])
        ..catalogFailures = 1
        ..pinned.add(_identity);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('offline-content/retry')),
          )
          .onPressed!;
      stale();
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(manager.catalogCalls, 2);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
      expect(find.text('จำเป็นต่อการเรียนที่กำลังดำเนินอยู่'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offline-content/remove/pack-a')),
        findsNothing,
      );
      expect(manager.downloaded, isEmpty);
      expect(manager.removed, isEmpty);
      expect(manager.repaired, isEmpty);
    },
  );

  for (final fail in [false, true]) {
    testWidgets('AC disposed repair completion is inert failure=$fail', (
      tester,
    ) async {
      final manager = _FakeManager([_state(OfflineContentStatus.quarantined)]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('offline-content/repair/pack-a')),
          )
          .onPressed!;
      stale();
      stale();
      await tester.pump();
      expect(manager.repaired, [_identity]);
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        manager.repairCompleter.completeError(StateError('late repair'));
      } else {
        manager.repairCompleter.complete(_state(OfflineContentStatus.verified));
      }
      stale();
      await tester.pumpAndSettle();
      expect(manager.catalogCalls, 1);
      expect(manager.repaired, [_identity]);
      expect(tester.takeException(), isNull);
    });
    testWidgets('AC disposed cancel completion is inert failure=$fail', (
      tester,
    ) async {
      final manager = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('offline-content/cancel/pack-a')),
          )
          .onPressed!;
      stale();
      stale();
      await tester.pump();
      expect(manager.cancelled, [_identity]);
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        manager.cancelPending!.completeError(StateError('late cancel'));
      } else {
        manager.cancelPending!.complete(false);
      }
      stale();
      await tester.pumpAndSettle();
      expect(manager.cancelled, [_identity]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AC late canRemove cannot continue metadata after replacement', (
    tester,
  ) async {
    final old = _FakeManager([_state(OfflineContentStatus.verified)])
      ..canRemovePending = Completer<bool>();
    final next = _FakeManager([]);
    Widget screen(_FakeManager manager) => MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    );
    await tester.pumpWidget(screen(old));
    await tester.pump();
    await tester.pumpWidget(screen(next));
    await tester.pumpAndSettle();
    old.canRemovePending!.complete(true);
    await tester.pumpAndSettle();
    expect(old.metadataReads, isEmpty);
    expect(next.metadataReads, isEmpty);
    expect(
      find.text('ยังไม่มีแพ็กเนื้อหาที่รองรับการใช้งานออฟไลน์'),
      findsOneWidget,
    );
  });

  testWidgets(
    'AC old cancellation completion cannot affect replacement download',
    (tester) async {
      final old = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      final next = _FakeManager([_state(OfflineContentStatus.downloading)])
        ..cancelPending = Completer<bool>();
      Widget screen(_FakeManager manager) => MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      );
      final cancel = find.byKey(
        const ValueKey('offline-content/cancel/pack-a'),
      );
      await tester.pumpWidget(screen(old));
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pump();
      await tester.pumpWidget(screen(next));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
      await tester.tap(cancel);
      await tester.pump();
      old.cancelPending!.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('ไม่มีการดาวน์โหลดที่ยกเลิกได้แล้ว'), findsNothing);
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      next.cancelPending!.complete(true);
      await tester.pumpAndSettle();
      expect(next.cancelled, [_identity]);
    },
  );

  testWidgets('AC catalog completion after disposal has no metadata work', (
    tester,
  ) async {
    final manager = _FakeManager([])
      ..catalogPending = Completer<List<OfflineContentState>>();
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    manager.catalogPending!.complete([_state(OfflineContentStatus.verified)]);
    await tester.pumpAndSettle();
    expect(manager.metadataReads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AC catalog retry is read-only, bounded and accessible at 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final manager = _FakeManager([])..catalogFailures = 2;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('offline-content/retry'));
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    expect(
      tester.getSemantics(retry),
      matchesSemantics(
        label: 'ลองอ่านสถานะอีกครั้ง',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('อ่านสถานะเนื้อหาออฟไลน์ไม่ได้'), findsOneWidget);
    expect(find.textContaining('private failure'), findsNothing);
    manager.catalogPending = Completer<List<OfflineContentState>>();
    final callback = tester.widget<FilledButton>(retry).onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(manager.catalogCalls, 3);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    manager.catalogPending!.complete([]);
    await tester.pumpAndSettle();
    expect(
      find.text('ยังไม่มีแพ็กเนื้อหาที่รองรับการใช้งานออฟไลน์'),
      findsOneWidget,
    );
    expect(manager.downloaded, isEmpty);
    expect(manager.removed, isEmpty);
    expect(manager.repaired, isEmpty);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('AC retry checks live gate and ignores a disposed callback', (
    tester,
  ) async {
    var enabled = true;
    final manager = _FakeManager([])..catalogFailures = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => enabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('offline-content/retry')),
        )
        .onPressed!;
    enabled = false;
    retry();
    await tester.pump();
    expect(manager.catalogCalls, 1);
    enabled = true;
    await tester.pumpWidget(const SizedBox());
    retry();
    await tester.pump();
    expect(manager.catalogCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AC late catalog never reads replacement manager metadata', (
    tester,
  ) async {
    final old = _FakeManager([])
      ..catalogPending = Completer<List<OfflineContentState>>();
    final next = _FakeManager([]);
    Widget screen(_FakeManager manager) => MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    );
    await tester.pumpWidget(screen(old));
    await tester.pumpWidget(screen(next));
    await tester.pumpAndSettle();
    old.catalogPending!.complete([_state(OfflineContentStatus.verified)]);
    await tester.pumpAndSettle();
    expect(next.metadataReads, isEmpty);
    expect(
      find.text('ยังไม่มีแพ็กเนื้อหาที่รองรับการใช้งานออฟไลน์'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AC replaced operation cannot clear current busy or show old failure',
    (tester) async {
      final old = _FakeManager([_state(OfflineContentStatus.quarantined)]);
      final next = _FakeManager([_state(OfflineContentStatus.quarantined)]);
      Widget screen(_FakeManager manager) => MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      );
      await tester.pumpWidget(screen(old));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('offline-content/repair/pack-a')),
      );
      await tester.pump();
      await tester.pumpWidget(screen(next));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('offline-content/repair/pack-a')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('offline-content/repair/pack-a')),
      );
      await tester.pump();
      old.repairCompleter.completeError(StateError('old operation'));
      await tester.pumpAndSettle();
      expect(
        find.text('จัดการเนื้อหาออฟไลน์ไม่สำเร็จ ลองใหม่ได้'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('offline-content/busy/pack-a')),
        findsOneWidget,
      );
      expect(next.catalogCalls, 1);
      next.repairCompleter.complete(_state(OfflineContentStatus.verified));
      await tester.pumpAndSettle();
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
    },
  );

  testWidgets('AC detached action cannot target replacement manager', (
    tester,
  ) async {
    final old = _FakeManager([_state(OfflineContentStatus.notDownloaded)]);
    final next = _FakeManager([_state(OfflineContentStatus.notDownloaded)]);
    Widget screen(_FakeManager manager) => MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    );
    await tester.pumpWidget(screen(old));
    await tester.pumpAndSettle();
    final stale = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
        )
        .onPressed!;
    await tester.pumpWidget(screen(next));
    await tester.pumpAndSettle();
    stale();
    await tester.pumpAndSettle();
    expect(next.downloaded, isEmpty);
    expect(old.downloaded, isEmpty);
  });

  for (final status in OfflineContentStatus.values) {
    testWidgets('optional offline context reports actual ${status.name}', (
      tester,
    ) async {
      final state = _state(status, bytes: 8192);
      final registry = MenuActionRegistry(currentOwner: () => 'test');
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: OfflineContentManagerScreen(
              manager: _FakeManager([state]),
              canInvoke: () => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final data = jsonDecode(
        (registry.snapshot()['context'] as List).single['value'] as String,
      );
      expect(data['status'], status.name);
      expect(data['verified'], state.hasVerifiedBytes);
      expect(data['downloadedBytes'], state.downloadedBytes);
      expect(data['manifestBytes'], 4096);
      expect(data.containsKey('requiredBytes'), false);
      expect(
        data['byteCountMeaning'],
        state.hasVerifiedBytes
            ? 'installed-total-including-adapter-files'
            : 'downloaded-so-far-not-verified',
      );
      expect(data['byteCountsComparableAsProgress'], false);
      expect(data['nativeActionsEnabled'], false);
      expect(data['revision'], state.identity.revision);
      expect(data.containsKey('path'), false);
      expect(registry.snapshot()['actions'], isEmpty);
    });
  }

  testWidgets('B08 shows manifest size and cancels a pending download', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.notDownloaded)])
      ..waitDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('พื้นที่ไฟล์อย่างน้อย 4.0 KB'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/cancel/pack-a')),
    );
    await tester.pumpAndSettle();
    expect(manager.cancelled, [_identity]);
    expect(find.text('การดาวน์โหลดถูกขัดจังหวะ'), findsOneWidget);
    expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsNothing);
  });

  testWidgets(
    'offline primary label is faithful with exact identity available in details',
    (tester) async {
      final manager = _FakeManager([
        _state(OfflineContentStatus.verified, bytes: 4096),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('pack-a'), findsNothing);
      expect(find.textContaining('4.0 KB'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('offline-content/details/pack-a')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('pack-a'), findsOneWidget);
      expect(find.textContaining('รุ่น 1'), findsOneWidget);
      expect(find.textContaining('4096 ไบต์'), findsOneWidget);
    },
  );

  for (final mismatch in [false, true]) {
    testWidgets(
      'offline pack title requires matching verified revision mismatch=$mismatch',
      (tester) async {
        const identity = ContentIdentity(
          type: ContentType.learningPack,
          id: 'pack-a',
          revision: 1,
        );
        final manager = _FakeManager([
          _state(OfflineContentStatus.notDownloaded, identity: identity),
        ]);
        final pack = LearningPackSummary(
          packId: 'pack-a',
          revision: mismatch ? 2 : 1,
          title: 'คำศัพท์สำหรับการเดินทาง',
          cefrLevel: 'A1',
          topic: 'travel',
          skill: 'recognition',
          goal: 'practice',
          contentIdentity: ContentIdentity(
            type: ContentType.learningPack,
            id: 'pack-a',
            revision: mismatch ? 2 : 1,
          ),
        );
        await tester.pumpWidget(_withPackMetadata(manager, pack));
        await tester.pumpAndSettle();
        expect(
          find.text('คำศัพท์สำหรับการเดินทาง'),
          mismatch ? findsNothing : findsOneWidget,
        );
        if (mismatch) expect(find.text('ชุดเนื้อหาการเรียน'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'f44 screen renders verified state and removes only local bytes',
    (tester) async {
      final manager = _FakeManager(<OfflineContentState>[
        _state(
          OfflineContentStatus.verified,
          localPath: '${List<String>.filled(64, 'a').join()}.content',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ไฟล์สำหรับใช้งานออฟไลน์'), findsOneWidget);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('offline-content/remove/pack-a')),
      );
      await tester.pumpAndSettle();

      expect(manager.removed, <ContentIdentity>[_identity]);
      expect(find.textContaining('ยังไม่ได้ดาวน์โหลด'), findsOneWidget);
    },
  );

  testWidgets('f44 quarantine offers repair and serializes item actions', (
    tester,
  ) async {
    final manager = _FakeManager(<OfflineContentState>[
      _state(OfflineContentStatus.quarantined),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('offline-content/repair/pack-a')),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('offline-content/busy/pack-a')),
          )
          .onPressed,
      isNull,
    );
    manager.repairCompleter.complete(_state(OfflineContentStatus.verified));
    await tester.pumpAndSettle();
    expect(manager.repaired, <ContentIdentity>[_identity]);
  });

  testWidgets('f44 kill switch fences a stale action before invocation', (
    tester,
  ) async {
    var enabled = true;
    final manager = _FakeManager(<OfflineContentState>[
      _state(OfflineContentStatus.notDownloaded),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => enabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stale = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
        )
        .onPressed!;

    enabled = false;
    stale();
    await tester.pump();
    expect(manager.downloaded, isEmpty);
  });

  testWidgets(
    'f44 review pinned revision exposes exact identity and no remove action',
    (tester) async {
      final manager = _FakeManager(<OfflineContentState>[
        _state(
          OfflineContentStatus.verified,
          localPath: '${List<String>.filled(64, 'a').join()}.content',
        ),
      ])..pinned.add(_identity);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final details = find.byKey(
        const ValueKey('offline-content/details/pack-a'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('รหัส: pack-a · รุ่น 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offline-content/remove/pack-a')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('จำเป็นต่อการเรียนที่กำลังดำเนินอยู่'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _feedbackVisibilityTransition(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigator,
  String transition,
) async {
  if (transition == 'route') {
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('synthetic cover')),
    ));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
  } else if (transition == 'app') {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  await tester.pumpAndSettle();
}

const _identity = ContentIdentity(
  type: ContentType.offlineArtifact,
  id: 'pack-a',
  revision: 1,
);

OfflineContentState _state(
  OfflineContentStatus status, {
  String? localPath,
  int bytes = 4,
  ContentIdentity identity = _identity,
}) => OfflineContentState(
  manifestId: 'manifest:pack-a:r1',
  identity: identity,
  status: status,
  localPath: status == OfflineContentStatus.verified
      ? localPath ?? '${List<String>.filled(64, 'a').join()}.content'
      : localPath,
  downloadedBytes: status == OfflineContentStatus.verified ? bytes : 0,
  verifiedChecksumSha256: status == OfflineContentStatus.verified
      ? List<String>.filled(64, 'a').join()
      : null,
  failureCode: status == OfflineContentStatus.quarantined
      ? OfflineContentFailureCode.checksumMismatch
      : status == OfflineContentStatus.interrupted
      ? OfflineContentFailureCode.interrupted
      : null,
  updatedAtUtc: DateTime.utc(2026, 8, 30),
);

Widget _withPackMetadata(
  OfflineContentManager manager,
  LearningPackSummary pack, {
  Completer<LearningPackDetail>? pending,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic:offline-title',
    nowUtc: () => DateTime.utc(2026, 9, 8),
  );
  final dependencies = AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    features: const BuildFeatureRegistry({
      Feature.studyPlanning: FeatureState.enabled,
    }),
    studyPlanning: StudyPlanningUseCases(
      packs: _PackRepository(pack, pending),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 9, 8),
      ),
    ),
  );
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    ),
  );
}

final class _PackRepository implements LearningPackRepository {
  _PackRepository(this.summary, this.pending);
  final Completer<LearningPackDetail>? pending;
  final LearningPackSummary summary;
  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async => [
    summary,
  ];
  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async =>
      pending?.future ??
      LearningPackDetail(summary: summary, vocabularyWordIds: const []);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-offline');
}

final class _FakeManager
    implements OfflineContentManager, OfflineContentDownloadControl {
  _FakeManager(this.values);

  final List<OfflineContentState> values;
  final downloaded = <ContentIdentity>[];
  final cancelled = <ContentIdentity>[];
  bool waitDownload = false;
  final downloadCompleter = Completer<OfflineContentState>();
  int catalogFailures = 0;
  int catalogCalls = 0;
  Completer<List<OfflineContentState>>? catalogPending;
  final metadataReads = <ContentIdentity>[];
  Completer<bool>? cancelPending;
  Completer<bool>? canRemovePending;

  @override
  Future<int> requiredBytes(ContentIdentity identity) async {
    metadataReads.add(identity);
    return 4096;
  }

  @override
  Future<bool> cancelDownload(ContentIdentity identity) async {
    cancelled.add(identity);
    if (cancelPending != null) return cancelPending!.future;
    downloadCompleter.complete(
      _replace(identity, OfflineContentStatus.interrupted),
    );
    return true;
  }

  final removed = <ContentIdentity>[];
  final repaired = <ContentIdentity>[];
  final pinned = <ContentIdentity>{};
  final repairCompleter = Completer<OfflineContentState>();

  @override
  Future<List<OfflineContentState>> catalog() async {
    catalogCalls++;
    if (catalogFailures > 0) {
      catalogFailures--;
      throw StateError('private failure');
    }
    return catalogPending?.future ?? List.of(values);
  }

  @override
  Future<bool> canRemove(ContentIdentity identity) async =>
      canRemovePending?.future ?? !pinned.contains(identity);

  @override
  Future<OfflineContentState> download(ContentIdentity identity) async {
    downloaded.add(identity);
    if (waitDownload) return downloadCompleter.future;
    return _replace(identity, OfflineContentStatus.verified);
  }

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) async {
    repaired.add(identity);
    final result = await repairCompleter.future;
    _replace(identity, result.status);
    return result;
  }

  @override
  Future<int> removeBytes(ContentIdentity identity) async {
    removed.add(identity);
    _replace(identity, OfflineContentStatus.notDownloaded);
    return 0;
  }

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) async =>
      values.singleWhere((state) => state.identity == identity);

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> reconcile() async {}

  OfflineContentState _replace(
    ContentIdentity identity,
    OfflineContentStatus status,
  ) {
    final index = values.indexWhere((state) => state.identity == identity);
    final next = _state(
      status,
      identity: identity,
      localPath: status == OfflineContentStatus.verified
          ? '${List<String>.filled(64, 'a').join()}.content'
          : null,
    );
    values[index] = next;
    return next;
  }
}
