import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/presentation/learning_time_binding.dart';
import 'package:vocab_learning_app/features/learning_time/presentation/recorded_time_view.dart';
import 'package:vocab_learning_app/screens/learning_time_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hiding seals confirmed time; visible return needs explicit ready',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      var visible = true;
      final binding = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => visible,
      );
      addTearDown(binding.dispose);
      expect(await binding.ready(_source()), isTrue);
      h.advance(2000000);
      binding.interacted();
      visible = false;
      binding.syncVisibility();
      await h.time.retryPending();
      expect(h.repo.total, 2000000);
      final hiddenGeneration = binding.visibilityGeneration;
      visible = true;
      binding.syncVisibility();
      expect(binding.visibilityGeneration, greaterThan(hiddenGeneration));
      h.advance(10000000);
      binding.interacted();
      expect(h.repo.total, 2000000);
      expect(await binding.ready(_source()), isTrue);
      h.advance(3000000);
      binding.interacted();
      binding.dispose();
      await h.time.retryPending();
      expect(h.repo.total, 5000000);
    },
  );

  testWidgets('background return cannot re-arm the collector', (tester) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    final binding = LearningTimeBinding(
      time: h.time,
      expectedOwnerId: 'owner-a',
      visible: () => true,
    );
    addTearDown(binding.dispose);
    expect(await binding.ready(_source()), isTrue);
    binding.didChangeAppLifecycleState(AppLifecycleState.paused);
    binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
    h.advance(5000000);
    binding.interacted();
    binding.close();
    await h.time.retryPending();
    expect(h.repo.segments, isEmpty);
  });

  testWidgets('hide/show during admission retires that ready request', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    final gate = Completer<void>();
    h.repo.admitGate = gate;
    var visible = true;
    final binding = LearningTimeBinding(
      time: h.time,
      expectedOwnerId: 'owner-a',
      visible: () => visible,
    );
    addTearDown(binding.dispose);
    final opening = binding.ready(_source());
    visible = false;
    binding.syncVisibility();
    visible = true;
    binding.syncVisibility();
    gate.complete();
    expect(await opening, isFalse);
    h.advance(5000000);
    binding.interacted();
    expect(h.repo.segments, isEmpty);
  });

  testWidgets('owner ABA permanently retires the old binding', (tester) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    final binding = LearningTimeBinding(
      time: h.time,
      expectedOwnerId: 'owner-a',
      visible: () => true,
    );
    addTearDown(binding.dispose);
    expect(await binding.ready(_source()), isTrue);
    h.owners.add(null);
    h.owners.add('owner-a');
    await tester.pump();
    expect(binding.current, isFalse);
    expect(await binding.ready(_source()), isFalse);
  });

  testWidgets(
    'policy change allows a fresh explicit ready, never old lease revival',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      final binding = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => true,
      );
      addTearDown(binding.dispose);
      expect(await binding.ready(_source()), isTrue);
      final old = binding.lease;
      h.repo.emit(false, 2);
      await tester.pump();
      h.repo.emit(true, 3);
      await tester.pump();
      expect(binding.lease, isNull);
      expect(await binding.ready(_source()), isTrue);
      expect(identical(binding.lease, old), isFalse);
    },
  );

  testWidgets(
    'explicit next context re-arms only after pending ACK and LIVE re-admission',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      final binding = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => true,
      );
      expect(await binding.ready(_source()), isTrue);
      h.advance(2000000);
      binding.interacted();
      final gate = Completer<void>();
      h.repo.segmentGate = gate;
      expect(await binding.ready(_source(stage: 2)), isFalse);
      gate.complete();
      await h.time.retryPending();
      await tester.pump();
      await tester.pump();
      h.advance(3000000);
      binding.interacted();
      binding.dispose();
      await h.time.retryPending();
      expect(h.repo.total, 5000000);
      expect(
        h.repo.segments.map(
          (s) => jsonDecode(s.eligibilityContextJson)['readingStage'],
        ),
        [1, 2],
      );
    },
  );

  testWidgets(
    'a legitimate detached closed scope can link after binding dispose',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      final binding = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => true,
      );
      expect(await binding.ready(_source()), isTrue);
      h.advance(2000000);
      binding.interacted();
      binding.dispose();
      await h.time.retryPending();
      final link = await binding.prepareSessionLink(_Receipt());
      expect(link, isNotNull);
      expect(binding.acknowledgeSessionLink(link!), isTrue);
      await h.time.retryPending();
      expect(h.repo.links, 1);
      expect(h.repo.total, 2000000);
    },
  );

  testWidgets('retired dependencies deny a previously disposed closed link', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    final binding = LearningTimeBinding(
      time: h.time,
      expectedOwnerId: 'owner-a',
      visible: () => true,
    );
    expect(await binding.ready(_source()), isTrue);
    h.advance(2000000);
    binding.interacted();
    binding.dispose();
    await h.time.retryPending();
    final lease = binding.lease!;
    binding.retireDependencies();
    expect(await binding.prepareSessionLink(_Receipt()), isNull);
    expect(await h.time.prepareSessionLink(lease, _Receipt()), isNull);
    expect(h.repo.total, 2000000);
    expect(h.repo.links, 0);
  });

  testWidgets(
    'a superseded visible binding cannot steal the slot after old ACK',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      final a = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => true,
      );
      final b = LearningTimeBinding(
        time: h.time,
        expectedOwnerId: 'owner-a',
        visible: () => true,
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(await a.ready(_source()), isTrue);
      h.advance(2000000);
      a.interacted();
      await b.ready(_source(document: 'second-visible-document'));
      await h.time.retryPending();
      await tester.pump();
      await tester.pump();
      expect(h.time.liveLease, same(b.lease));
      h.advance(3000000);
      a.interacted();
      b.interacted();
      b.close();
      await h.time.retryPending();
      expect(h.repo.total, 5000000);
    },
  );

  testWidgets(
    'readback reads acknowledged history without admitting any source',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      h.repo.value = const RecordedTimeRead.recorded(
        activeDurationUs: 61000000,
        segmentCount: 2,
      );
      await tester.pumpWidget(
        _app(
          RecordedTimeView(
            time: h.time,
            expectedOwnerId: 'owner-a',
            target: const OwnerTimeRead(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1 minute 1 second'), findsOneWidget);
      expect(h.repo.admissions, 0);
      expect(h.repo.preferenceWrites, 0);
    },
  );

  testWidgets('late acknowledged read cannot enter the next owner generation', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    final read = Completer<RecordedTimeRead>();
    h.repo.readGate = read;
    await tester.pumpWidget(
      _app(
        RecordedTimeView(
          time: h.time,
          expectedOwnerId: 'owner-a',
          target: const OwnerTimeRead(),
        ),
      ),
    );
    h.owners.add(null);
    h.owners.add('owner-a');
    read.complete(
      const RecordedTimeRead.recorded(
        activeDurationUs: 5000000,
        segmentCount: 1,
      ),
    );
    await _flushTimeEvents(tester);
    expect(find.text('5 seconds'), findsNothing);
    expect(find.text('Recorded time is unavailable'), findsOneWidget);
  });

  testWidgets(
    'default-off choice is explicit and readback still creates no source',
    (tester) async {
      final h = await _Harness.open(tester, enabled: false);
      addTearDown(h.close);
      await tester.pumpWidget(
        _app(
          LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.text('No recorded time yet'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(h.repo.preference.enabled, isTrue);
      expect(h.repo.admissions, 0);
    },
  );

  testWidgets('captured settings callback cannot change an owner after ABA', (
    tester,
  ) async {
    final h = await _Harness.open(tester, enabled: false);
    addTearDown(h.close);
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
      ),
    );
    final callback = tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .onChanged!;
    h.owners.add(null);
    h.owners.add('owner-a');
    await _flushTimeEvents(tester);
    callback(true);
    await tester.pump();
    expect(h.repo.preferenceWrites, 0);
    expect(find.text('Settings are unavailable for this user'), findsOneWidget);
  });

  testWidgets(
    'covered settings callback cannot start a new preference command',
    (tester) async {
      final h = await _Harness.open(tester, enabled: false);
      addTearDown(h.close);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
          navigator: navigator,
        ),
      );
      final callback = tester
          .widget<SwitchListTile>(find.byType(SwitchListTile))
          .onChanged!;
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      callback(true);
      await tester.pump();
      expect(h.repo.preferenceWrites, 0);
    },
  );

  testWidgets('unavailable settings keeps the standard Back exit usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const LearningTimeSettingsScreen(
                    time: null,
                    expectedOwnerId: 'unavailable',
                  ),
                ),
              ),
            ),
            child: const Text('Open time settings'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open time settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings are unavailable for this user'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open time settings'), findsOneWidget);
  });

  testWidgets('visibility epoch remains available without an owner authority', (
    tester,
  ) async {
    var visible = true;
    final binding = LearningTimeBinding(
      time: null,
      expectedOwnerId: 'unavailable',
      visible: () => visible,
    );
    addTearDown(binding.dispose);
    expect(binding.hostVisible, isTrue);
    expect(binding.current, isFalse);
    final original = binding.visibilityGeneration;
    visible = false;
    binding.syncVisibility();
    visible = true;
    binding.syncVisibility();
    expect(binding.visibilityGeneration, greaterThan(original));
    expect(binding.hostVisible, isTrue);
    expect(binding.current, isFalse);
  });

  testWidgets('cached settings callback stays retired after cover and return', (
    tester,
  ) async {
    final h = await _Harness.open(tester, enabled: false);
    addTearDown(h.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
        navigator: navigator,
      ),
    );
    final stale = tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .onChanged!;
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    stale(true);
    await tester.pump();
    expect(h.repo.preferenceWrites, 0);
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pump();
    expect(h.repo.preferenceWrites, 1);
  });

  testWidgets('cached settings callback cannot use a replacement dependency', (
    tester,
  ) async {
    final a = await _Harness.open(tester, enabled: false);
    final b = await _Harness.open(tester, enabled: false);
    addTearDown(a.close);
    addTearDown(b.close);
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(
          key: const Key('settings'),
          time: a.time,
          expectedOwnerId: 'owner-a',
        ),
      ),
    );
    final stale = tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .onChanged!;
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(
          key: const Key('settings'),
          time: b.time,
          expectedOwnerId: 'owner-a',
        ),
      ),
    );
    stale(true);
    await tester.pump();
    expect(a.repo.preferenceWrites, 0);
    expect(b.repo.preferenceWrites, 0);
  });

  testWidgets('late setting ACK cannot change replacement widget state', (
    tester,
  ) async {
    final a = await _Harness.open(tester, enabled: false);
    final b = await _Harness.open(tester, enabled: false);
    addTearDown(a.close);
    addTearDown(b.close);
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(
          key: const Key('settings'),
          time: a.time,
          expectedOwnerId: 'owner-a',
        ),
      ),
    );
    final gate = Completer<void>();
    a.repo.preferenceGate = gate;
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pump();
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(
          key: const Key('settings'),
          time: b.time,
          expectedOwnerId: 'owner-a',
        ),
      ),
    );
    gate.complete();
    await a.time.retryPending();
    await tester.pump();
    final current = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(current.value, isFalse);
    expect(current.onChanged, isNotNull);
    expect(b.repo.preferenceWrites, 0);
  });

  testWidgets('background and return retire the old settings action', (
    tester,
  ) async {
    final h = await _Harness.open(tester, enabled: false);
    addTearDown(h.close);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      _app(
        LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
      ),
    );
    final stale = tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .onChanged!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    stale(true);
    expect(h.repo.preferenceWrites, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    stale(true);
    await tester.pump();
    expect(h.repo.preferenceWrites, 0);
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pump();
    expect(h.repo.preferenceWrites, 1);
  });

  testWidgets(
    'private history clears on cover and only a fresh read returns it',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      h.repo.value = const RecordedTimeRead.recorded(
        activeDurationUs: 42000000,
        segmentCount: 1,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          RecordedTimeView(
            time: h.time,
            expectedOwnerId: 'owner-a',
            target: const OwnerTimeRead(),
          ),
          navigator: navigator,
        ),
      );
      await tester.pump();
      expect(find.text('42 seconds'), findsOneWidget);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('42 seconds', skipOffstage: false), findsNothing);
      final read = Completer<RecordedTimeRead>();
      h.repo.readGate = read;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('42 seconds'), findsNothing);
      read.complete(h.repo.value);
      await _flushTimeEvents(tester);
      expect(find.text('42 seconds'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('42 seconds', skipOffstage: false), findsNothing);
      final foregroundRead = Completer<RecordedTimeRead>();
      h.repo.readGate = foregroundRead;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('42 seconds'), findsNothing);
      foregroundRead.complete(h.repo.value);
      await _flushTimeEvents(tester);
      expect(find.text('42 seconds'), findsOneWidget);
      expect(h.repo.admissions, 0);
    },
  );

  testWidgets(
    'cached read-again action cannot revive after cover or dependency replacement',
    (tester) async {
      final a = await _Harness.open(tester);
      final b = await _Harness.open(tester);
      addTearDown(a.close);
      addTearDown(b.close);
      a.repo.value = const RecordedTimeRead.unavailable();
      b.repo.value = const RecordedTimeRead.unavailable();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          RecordedTimeView(
            key: const Key('read'),
            time: a.time,
            expectedOwnerId: 'owner-a',
            target: const OwnerTimeRead(),
          ),
          navigator: navigator,
        ),
      );
      await tester.pump();
      final stale = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Read again'))
          .onPressed!;
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      final reads = a.repo.reads;
      stale();
      await tester.pump();
      expect(a.repo.reads, reads);
      await tester.pumpWidget(
        _app(
          RecordedTimeView(
            key: const Key('read'),
            time: b.time,
            expectedOwnerId: 'owner-a',
            target: const OwnerTimeRead(),
          ),
          navigator: navigator,
        ),
      );
      await tester.pump();
      final bReads = b.repo.reads;
      stale();
      await tester.pump();
      expect(a.repo.reads, reads);
      expect(b.repo.reads, bReads);
    },
  );

  testWidgets('cached pending retry cannot restart after cover and return', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    addTearDown(h.close);
    h.repo.failSegments = true;
    final lease = await h.time.attach(_source(), stillCurrent: () => true);
    expect(await h.time.ready(lease!), isTrue);
    h.advance(2000000);
    h.time.interacted(lease);
    h.time.detach(lease);
    await h.time.retryPending();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        RecordedTimeView(
          time: h.time,
          expectedOwnerId: 'owner-a',
          target: const OwnerTimeRead(),
        ),
        navigator: navigator,
      ),
    );
    await tester.pump();
    final stale = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Retry saving'))
        .onPressed!;
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final attempts = h.repo.segmentAttempts;
    stale();
    await tester.pump();
    expect(h.repo.segmentAttempts, attempts);
    h.repo.failSegments = false;
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Retry saving'))
        .onPressed!();
    await tester.pump();
    expect(h.repo.segmentAttempts, attempts + 1);
  });

  testWidgets(
    'Back ignores owner invalidity but rejects an old visibility epoch',
    (tester) async {
      final h = await _Harness.open(tester);
      addTearDown(h.close);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(const Text('Home'), navigator: navigator));
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => LearningTimeSettingsScreen(
              time: h.time,
              expectedOwnerId: 'owner-a',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<BackButton>(find.byType(BackButton))
          .onPressed!;
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      h.owners.add(null);
      await tester.pump();
      stale();
      await tester.pump();
      expect(find.byType(LearningTimeSettingsScreen), findsOneWidget);
      tester.widget<BackButton>(find.byType(BackButton)).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('pending setting does not trap the explicit Back exit', (
    tester,
  ) async {
    final h = await _Harness.open(tester, enabled: false);
    addTearDown(h.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(const Text('Home'), navigator: navigator));
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => LearningTimeSettingsScreen(
            time: h.time,
            expectedOwnerId: 'owner-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    h.repo.preferenceGate = gate;
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pump();
    expect(h.time.pendingState, LearningTimePendingState.preference);
    tester.widget<BackButton>(find.byType(BackButton)).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    gate.complete();
    await h.time.retryPending();
  });

  for (final thai in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'settings wraps at320/200 withIME ${thai ? 'Thai' : 'English'} $brightness',
        (tester) async {
          final h = await _Harness.open(tester, enabled: false);
          addTearDown(h.close);
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              _app(
                MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 640),
                    textScaler: TextScaler.linear(2),
                    viewInsets: EdgeInsets.only(bottom: 240),
                    disableAnimations: true,
                  ),
                  child: LearningTimeSettingsScreen(
                    time: h.time,
                    expectedOwnerId: 'owner-a',
                  ),
                ),
                thai: thai,
                brightness: brightness,
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              find.text(
                thai ? 'บันทึกเวลาจากการโต้ตอบ' : 'Record interaction time',
              ),
              findsOneWidget,
            );
            await tester.drag(find.byType(ListView), const Offset(0, -1600));
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(h.repo.admissions, 0);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('native switch remains keyboard/semantics operable', (
    tester,
  ) async {
    final h = await _Harness.open(tester, enabled: false);
    addTearDown(h.close);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _app(
          LearningTimeSettingsScreen(time: h.time, expectedOwnerId: 'owner-a'),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.repo.preference.enabled, isTrue);
      expect(h.repo.preferenceWrites, 1);
    } finally {
      semantics.dispose();
    }
  });

  test('formatting rounds once after the acknowledged microsecond sum', () {
    expect(formatRecordedLearningTime(1, thai: false), 'Less than 1 second');
    expect(formatRecordedLearningTime(59999999, thai: true), '1 นาที');
    expect(
      formatRecordedLearningTime(3601000000, thai: false),
      '1 hour 1 second',
    );
  });
}

Future<void> _flushTimeEvents(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Widget _app(
  Widget child, {
  bool thai = false,
  Brightness brightness = Brightness.light,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  locale: Locale(thai ? 'th' : 'en'),
  supportedLocales: const [Locale('en'), Locale('th')],
  localizationsDelegates: const [_AllLocaleMaterial(), _AllLocaleCupertino()],
  theme: ThemeData(brightness: brightness, platform: TargetPlatform.android),
  home: Scaffold(body: child),
);

final class _AllLocaleMaterial
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _AllLocaleMaterial();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const DefaultMaterialLocalizations(),
      );
  @override
  bool shouldReload(_AllLocaleMaterial old) => false;
}

final class _AllLocaleCupertino
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AllLocaleCupertino();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const DefaultCupertinoLocalizations(),
      );
  @override
  bool shouldReload(_AllLocaleCupertino old) => false;
}

ReadingTimeSource _source({
  int stage = 1,
  String document = 'synthetic-visible-document',
}) => ReadingTimeSource(
  documentId: document,
  documentRevision: 1,
  snapshotSha256: 'a' * 64,
  targetPinsSha256: 'b' * 64,
  readingStage: stage,
  callerContext: LearningTimeCallerContext.ordinary,
);

final class _Harness {
  _Harness(bool enabled)
    : repo = _Repository(enabled),
      _creationZone = Zone.current;
  final Zone _creationZone;
  final _Repository repo;
  final owners = StreamController<String?>.broadcast(sync: true);
  late final LearningTimeUseCases time;
  int us = 0;
  int id = 0;
  static Future<_Harness> open(
    WidgetTester tester, {
    bool enabled = true,
  }) async => (await tester.runAsync<_Harness>(() async {
    final h = _Harness(enabled);
    h.time = LearningTimeUseCases(
      repository: h.repo,
      ownerChanges: h.owners.stream,
      monotonicMicros: () => h.us,
      nowUtc: () =>
          DateTime.utc(2026, 10, 31).add(Duration(microseconds: h.us)),
      generateId: () => 'ui-${h.id++}',
    );
    h.owners.add('owner-a');
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
    }
    return h;
  }))!;

  void advance(int micros) => us += micros;
  Future<void> close() => _creationZone.run(() async {
    await time.dispose();
    await owners.close();
    await repo.controller.close();
  });
}

final class _Repository implements LearningTimeRepository {
  _Repository(bool enabled)
    : preference = LearningTimePreference(
        ownerId: 'owner-a',
        enabled: enabled,
        revision: 1,
        updatedAtUtcMs: 1,
      );
  LearningTimePreference preference;
  final controller = StreamController<LearningTimePreference?>.broadcast(
    sync: true,
  );
  final segments = <ClosedTimeSegmentIntent>[];
  int admissions = 0;
  int preferenceWrites = 0;
  int links = 0;
  int reads = 0;
  int segmentAttempts = 0;
  bool failSegments = false;
  Completer<void>? admitGate;
  Completer<void>? segmentGate;
  Completer<void>? preferenceGate;
  Completer<RecordedTimeRead>? readGate;
  RecordedTimeRead value = const RecordedTimeRead.noneRecorded();
  int get total => segments.fold(0, (sum, s) => sum + s.activeDurationUs);
  void emit(bool enabled, int revision) {
    preference = LearningTimePreference(
      ownerId: 'owner-a',
      enabled: enabled,
      revision: revision,
      updatedAtUtcMs: revision,
    );
    controller.add(preference);
  }

  @override
  Stream<LearningTimePreference?> watchPreference(String ownerId) async* {
    yield preference;
    yield* controller.stream;
  }

  @override
  Future<LearningTimePreference> readPreference({
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async => preference;
  @override
  Future<LearningTimePreference> commitPreference(
    LearningTimePreferenceIntent intent,
  ) async {
    final gate = preferenceGate;
    preferenceGate = null;
    if (gate != null) await gate.future;
    if (!intent.belongsTo(this) || !intent.isCurrent) {
      throw StateError('retired');
    }
    preferenceWrites++;
    preference = LearningTimePreference(
      ownerId: intent.ownerId,
      enabled: intent.enabled,
      revision: intent.expectedRevision + 1,
      updatedAtUtcMs: intent.updatedAtUtcMs,
    );
    controller.add(preference);
    return preference;
  }

  @override
  Future<TimeSourceAdmission> admitSource({
    required TimeSource source,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    final gate = admitGate;
    admitGate = null;
    if (gate != null) await gate.future;
    if (!isCurrent() || source is! ReadingTimeSource) {
      throw StateError('not ready');
    }
    admissions++;
    return TimeSourceAdmission(
      ownerId: expectedOwnerId,
      sourceKind: TimeSourceKind.reading,
      sourceBindingJson: source.sourceBindingJson,
      contextBindingJson: source.contextBindingJson,
      verifyClosed: (current) async {
        if (!current()) throw StateError('retired');
      },
    );
  }

  @override
  Future<void> commitSegment(ClosedTimeSegmentIntent intent) async {
    segmentAttempts++;
    if (failSegments) throw StateError('synthetic time store failure');
    final gate = segmentGate;
    segmentGate = null;
    if (gate != null) await gate.future;
    if (!intent.belongsTo(this) || !intent.isCurrent) {
      throw StateError('retired');
    }
    if (!segments.any((s) => s.id == intent.id)) segments.add(intent);
  }

  @override
  Future<TimeSessionLinkAdmission> prepareSessionLink({
    required LearningTimeScope scope,
    required CanonicalLearningTimeSessionLinkReceipt proof,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw StateError('retired');
    return TimeSessionLinkAdmission(
      ownerId: expectedOwnerId,
      scopeId: scope.id,
      linkedSessionId: proof.sessionId,
      sessionLinkBindingJson: jsonEncode({
        'schemaVersion': 1,
        'sessionId': proof.sessionId,
        'sourceBindingSha256': 'c' * 64,
        'canonicalSourceBindingSha256': 'c' * 64,
      }),
      verifyClosed: (current) async {
        if (!current()) throw StateError('retired');
      },
    );
  }

  @override
  Future<void> commitSessionLink(TimeSessionLinkIntent intent) async {
    if (!intent.isCurrent) throw StateError('retired');
    links++;
  }

  @override
  Future<RecordedTimeRead> read({
    required TimeReadTarget target,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    reads++;
    final gate = readGate;
    readGate = null;
    final result = gate == null ? value : await gate.future;
    return isCurrent() ? result : const RecordedTimeRead.unavailable();
  }
}

final class _Receipt implements CanonicalLearningTimeSessionLinkReceipt {
  @override
  String get ownerId => 'owner-a';
  @override
  String get sessionId => 'synthetic-actual-start';
  @override
  String get activityType => 'reading';
  @override
  CanonicalLearningTimeSourceKind get sourceKind =>
      CanonicalLearningTimeSourceKind.reading;
  @override
  String get sourceBindingJson => _source().sourceBindingJson;
}
