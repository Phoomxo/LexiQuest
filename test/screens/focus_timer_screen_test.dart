import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/focus_timer_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/review_center_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  testWidgets(
    'an already connected IME remains safe before owner-loss redraw',
    (tester) async {
      final owners = _owners();
      await _open(tester, owners, _Clock());
      await _reveal(tester, _key('focus-minutes'));
      await tester.enterText(_key('focus-minutes'), '99');
      owners.add(null);
      tester.testTextInput.enterText('66');
      await tester.pump();
      expect(tester.takeException(), isNull);
      _expectUnavailable(tester);
    },
  );

  testWidgets(
    'real controls configure, pause, resume, stop and manually finish',
    (tester) async {
      final owners = _owners();
      final clock = _Clock();
      await _open(tester, owners, clock);
      expect(_remaining(tester), '25:00');
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      clock.advance(const Duration(seconds: 10));
      await _tap(tester, 'focus-pause');
      expect(_remaining(tester), '00:50');
      clock.advance(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:50');
      await _tap(tester, 'focus-resume');
      clock.advance(const Duration(seconds: 5));
      await _tap(tester, 'focus-stop');
      expect(_remaining(tester), '01:00');
      await _tap(tester, 'focus-start');
      clock.advance(const Duration(seconds: 3));
      await _tap(tester, 'focus-finish');
      expect(_remaining(tester), '00:57');
      expect(_status(tester), 'Finished early');
      expect(_enabled(tester, 'focus-start'), isFalse);
      expect(_enabled(tester, 'focus-resume'), isFalse);
      await _tap(tester, 'focus-new-interval');
      expect(_remaining(tester), '01:00');
      expect(_enabled(tester, 'focus-start'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid minute drafts retain the last valid duration', (
    tester,
  ) async {
    final owners = _owners();
    await _open(tester, owners, _Clock());
    for (final invalid in ['', '1.5', '-1', '0', '181']) {
      await _configure(tester, invalid);
      expect(_field(tester).decoration?.errorText, isNotEmpty);
      expect(_remaining(tester), '25:00');
    }
    await _configure(tester, ' 1 ');
    expect(_field(tester).decoration?.errorText, isNull);
    expect(_remaining(tester), '01:00');
    await _configure(tester, '180');
    expect(_remaining(tester), '180:00');
    await _tap(tester, 'focus-start');
    await _reveal(tester, _key('focus-minutes'));
    expect(_field(tester).enabled, isFalse);
    expect(_enabled(tester, 'focus-configure'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'subsecond remaining time uses a ceiling and expiry finishes once',
    (tester) async {
      final owners = _owners();
      final clock = _Clock();
      await _open(tester, owners, clock);
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      clock.advance(const Duration(microseconds: 59999500));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:01');
      clock.advance(const Duration(microseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:00');
      expect(_status(tester), 'Interval complete');
      expect(_enabled(tester, 'focus-new-interval'), isTrue);
      expect(_enabled(tester, 'focus-start'), isFalse);
      expect(_enabled(tester, 'focus-resume'), isFalse);
      final completedStatus = _status(tester);
      clock.advance(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:00');
      expect(_status(tester), completedStatus);
    },
  );

  testWidgets('a retained Start cannot control a newer configuration', (
    tester,
  ) async {
    final owners = _owners();
    await _open(tester, owners, _Clock());
    final retained = _action(tester, 'focus-start');
    await _configure(tester, '2');
    retained();
    await tester.pump();
    expect(_remaining(tester), '02:00');
    expect(_enabled(tester, 'focus-start'), isTrue);
    expect(_enabled(tester, 'focus-pause'), isFalse);
  });

  testWidgets('a retained Stop cannot clear a replacement running interval', (
    tester,
  ) async {
    final owners = _owners();
    final clock = _Clock();
    await _open(tester, owners, clock);
    await _configure(tester, '1');
    await _tap(tester, 'focus-start');
    final retained = _action(tester, 'focus-stop');
    await _tap(tester, 'focus-stop');
    await _tap(tester, 'focus-start');
    clock.advance(const Duration(seconds: 5));
    retained();
    await tester.pump(const Duration(seconds: 1));
    expect(_remaining(tester), '00:55');
    expect(_enabled(tester, 'focus-pause'), isTrue);
    expect(_enabled(tester, 'focus-resume'), isFalse);
  });

  testWidgets(
    'an old Finish polls natural expiry before accepting its intent',
    (tester) async {
      final owners = _owners();
      final clock = _Clock();
      await _open(tester, owners, clock);
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      final finish = _action(tester, 'focus-finish');
      final stop = _action(tester, 'focus-stop');
      clock.advance(const Duration(minutes: 1));
      finish();
      stop();
      await tester.pump();
      expect(_remaining(tester), '00:00');
      expect(_status(tester), 'Interval complete');
      expect(_enabled(tester, 'focus-new-interval'), isTrue);
      expect(_enabled(tester, 'focus-start'), isFalse);
      expect(_enabled(tester, 'focus-resume'), isFalse);
    },
  );

  testWidgets('matching owner notifications do not reset a running interval', (
    tester,
  ) async {
    final owners = _owners();
    final clock = _Clock();
    await _open(tester, owners, clock);
    await _configure(tester, '1');
    await _tap(tester, 'focus-start');
    clock.advance(const Duration(seconds: 10));
    owners.add(_owner);
    await tester.pump(const Duration(seconds: 1));
    expect(_remaining(tester), '00:50');
    expect(_enabled(tester, 'focus-pause'), isTrue);
  });

  for (final reason in ['inactive', 'hidden-pane']) {
    testWidgets('$reason pauses until an explicit same-owner Resume', (
      tester,
    ) async {
      final owners = _owners();
      final clock = _Clock();
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await _mount(
        tester,
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          child: _screen(owners.stream, clock),
          builder: (_, value, child) =>
              Visibility.maintain(visible: value, child: child!),
        ),
      );
      owners.add(_owner);
      await _until(tester, () => _enabled(tester, 'focus-start'));
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      final retained = _action(tester, 'focus-stop');
      clock.advance(const Duration(seconds: 10));
      if (reason == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        visible.value = false;
      }
      await tester.pump();
      retained();
      clock.advance(const Duration(hours: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(_key('focus-remaining', offstage: true), findsNothing);
      expect(_key('focus-minutes', offstage: true), findsNothing);
      if (reason == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        visible.value = true;
      }
      await _until(tester, () => _enabled(tester, 'focus-resume'));
      expect(_remaining(tester), '00:50');
      await tester.pump(const Duration(seconds: 2));
      expect(_remaining(tester), '00:50');
      await _tap(tester, 'focus-resume');
      clock.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:45');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a second foreign cover never resumes or discards a paused interval',
    (tester) async {
      final owners = _owners();
      final clock = _Clock();
      final navigation = GlobalKey<NavigatorState>();
      await _open(tester, owners, clock, navigation: navigation);
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      final retained = _action(tester, 'focus-stop');
      clock.advance(const Duration(seconds: 10));
      final first = await _cover(tester, navigation, 'first foreign cover');
      clock.advance(const Duration(hours: 1));
      final second = await _cover(tester, navigation, 'second foreign cover');
      retained();
      await tester.pump();
      expect(second.isCurrent, isTrue);
      expect(_key('focus-remaining', offstage: true), findsNothing);
      navigation.currentState!.pop();
      await _until(tester, () => first.isCurrent);
      clock.advance(const Duration(hours: 1));
      navigation.currentState!.pop();
      await _until(tester, () => _enabled(tester, 'focus-resume'));
      expect(_remaining(tester), '00:50');
      expect(_enabled(tester, 'focus-pause'), isFalse);
      await _tap(tester, 'focus-resume');
      clock.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(_remaining(tester), '00:45');
      expect(tester.takeException(), isNull);
    },
  );

  for (final intermediate in <String?>[null, 'synthetic-focus-other-owner']) {
    testWidgets('pre-firstframe owner A-$intermediate-A stays unavailable', (
      tester,
    ) async {
      final owners = _owners();
      var emitted = false;
      await _mount(
        tester,
        home: Column(
          children: [
            Expanded(child: _screen(owners.stream, _Clock())),
            Builder(
              builder: (_) {
                if (!emitted) {
                  emitted = true;
                  owners
                    ..add(_owner)
                    ..add(intermediate)
                    ..add(_owner);
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      );
      owners.add(_owner);
      await tester.pump();
      _expectUnavailable(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sibling-build invalidation retires an existing editable minute field',
    (tester) async {
      final owners = _owners();
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      var invalidate = false;
      final screen = _screen(owners.stream, _Clock());
      await _mount(
        tester,
        home: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (_, value, _) => Column(
            children: [
              Expanded(child: screen),
              Builder(
                builder: (_) {
                  if (invalidate) {
                    invalidate = false;
                    owners
                      ..add(null)
                      ..add(_owner);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
      owners.add(_owner);
      await _until(tester, () => _enabled(tester, 'focus-start'));
      await _reveal(tester, _key('focus-minutes'));
      await tester.enterText(_key('focus-minutes'), '99');
      final submitted = _field(tester).onSubmitted!;
      final start = _action(tester, 'focus-start');
      invalidate = true;
      rebuild.value++;
      await tester.pump();
      tester.testTextInput.enterText('66');
      submitted('99');
      start();
      await tester.pump();
      _expectUnavailable(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidation in ['background-return', 'owner-ABA']) {
    testWidgets('retained minute submission is inert after $invalidation', (
      tester,
    ) async {
      final owners = _owners();
      await _open(tester, owners, _Clock());
      await _configure(tester, '1');
      final submitted = _field(tester).onSubmitted!;
      if (invalidation == 'owner-ABA') {
        owners
          ..add(null)
          ..add(_owner);
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pump();
      if (invalidation == 'background-return') {
        await _reveal(tester, _key('focus-minutes'));
        await tester.enterText(_key('focus-minutes'), '2');
      }
      submitted('2');
      await tester.pump();
      if (invalidation == 'owner-ABA') {
        _expectUnavailable(tester);
      } else {
        expect(_remaining(tester), '01:00');
        expect(_enabled(tester, 'focus-start'), isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(_remaining(tester), '02:00');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final event in ['null-to-same', 'other-to-same', 'error', 'done']) {
    testWidgets('owner $event invalidates captured controls before redraw', (
      tester,
    ) async {
      final owners = _owners();
      final clock = _Clock();
      await _open(tester, owners, clock);
      await _configure(tester, '1');
      await _tap(tester, 'focus-start');
      final retained = _action(tester, 'focus-finish');
      switch (event) {
        case 'null-to-same':
          owners
            ..add(null)
            ..add(_owner);
        case 'other-to-same':
          owners
            ..add('synthetic-focus-other-owner')
            ..add(_owner);
        case 'error':
          owners.addError(StateError('Synthetic focus owner failure'));
        case 'done':
          await owners.close();
      }
      retained();
      await tester.pump();
      _expectUnavailable(tester);
      if (!owners.isClosed) {
        owners.add(_owner);
      }
      await tester.pump();
      _expectUnavailable(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a blank expected owner cannot authorize a timer', (
    tester,
  ) async {
    final owners = _owners();
    await _mount(
      tester,
      home: _screen(owners.stream, _Clock(), expectedOwner: '   '),
    );
    owners.add('   ');
    await tester.pump();
    _expectUnavailable(tester);
    expect(tester.takeException(), isNull);
  });

  for (final replacement in [
    'dependencies',
    'stream',
    'clock',
    'expected-owner',
  ]) {
    testWidgets('$replacement replacement permanently retires an open timer', (
      tester,
    ) async {
      final owners = _owners();
      final newOwners = _owners();
      final clock = _Clock();
      final newClock = _Clock();
      final oldRead = clock.read;
      final newRead = newClock.read;
      final revision = ValueNotifier<int>(0);
      final dependencies = _dependencies();
      final newDependencies = _dependencies();
      addTearDown(revision.dispose);
      await _mount(
        tester,
        home: ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, value, _) => FocusTimerScreen(
            expectedOwnerId: value > 0 && replacement == 'expected-owner'
                ? 'synthetic-focus-other-owner'
                : _owner,
            ownerChanges: value > 0 && replacement == 'stream'
                ? newOwners.stream
                : owners.stream,
            monotonicMicros: value > 0 && replacement == 'clock'
                ? newRead
                : oldRead,
            languageCode: 'en',
          ),
        ),
        wrap: (child) => ValueListenableBuilder<int>(
          valueListenable: revision,
          child: child,
          builder: (_, value, child) => AppDependenciesScope(
            dependencies: value > 0 && replacement == 'dependencies'
                ? newDependencies
                : dependencies,
            child: child!,
          ),
        ),
      );
      owners.add(_owner);
      await _until(tester, () => _enabled(tester, 'focus-start'));
      await _tap(tester, 'focus-start');
      final retained = _action(tester, 'focus-stop');
      revision.value++;
      await tester.pump();
      retained();
      owners.add(_owner);
      newOwners.add(_owner);
      await tester.pump();
      _expectUnavailable(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalid in [false, true]) {
    for (final exit in ['untimed', 'back']) {
      testWidgets('$exit exit remains usable while owner invalid=$invalid', (
        tester,
      ) async {
        final owners = _owners();
        final navigation = GlobalKey<NavigatorState>();
        await _mount(
          tester,
          navigation: navigation,
          home: _launcher(navigation, () => _screen(owners.stream, _Clock())),
        );
        await _tap(tester, 'open-focus');
        await _until(tester, () => _timerRouteReady(tester));
        if (invalid) {
          owners
            ..add(_owner)
            ..add(null);
          await tester.pump();
        }
        expect(_key('focus-minutes'), findsNothing);
        await _leave(tester, back: exit == 'back');
        expect(find.byType(FocusTimerScreen), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('retained untimed and Back cannot pop a foreign top route', (
    tester,
  ) async {
    final owners = _owners();
    final navigation = GlobalKey<NavigatorState>();
    await _mount(
      tester,
      navigation: navigation,
      home: _launcher(navigation, () => _screen(owners.stream, _Clock())),
    );
    await _tap(tester, 'open-focus');
    owners.add(_owner);
    await _until(tester, () => _enabled(tester, 'focus-start'));
    final untimed = _action(tester, 'focus-untimed');
    final back = tester.widget<BackButton>(find.byType(BackButton)).onPressed;
    expect(back, isNotNull);
    final foreign = await _cover(tester, navigation, 'synthetic foreign exit');
    owners.add(null);
    untimed();
    back!();
    await tester.pump();
    expect(foreign.isCurrent, isTrue);
    expect(find.text('synthetic foreign exit'), findsOneWidget);
    navigation.currentState!.pop();
    await _until(tester, () => _timerRouteReady(tester));
    _expectUnavailable(tester);
    await _leave(tester, back: true);
    expect(find.byType(FocusTimerScreen), findsNothing);
  });

  testWidgets('a newly rendered covered Back icon cannot pop a foreign route', (
    tester,
  ) async {
    final owners = _owners();
    final navigation = GlobalKey<NavigatorState>();
    await _mount(
      tester,
      navigation: navigation,
      home: _launcher(navigation, () => _screen(owners.stream, _Clock())),
    );
    await _tap(tester, 'open-focus');
    owners.add(_owner);
    await _until(tester, () => _enabled(tester, 'focus-start'));
    final foreign = await _cover(
      tester,
      navigation,
      'synthetic covered Back fallback',
    );
    final appBar = find.descendant(
      of: find.byType(FocusTimerScreen, skipOffstage: false),
      matching: find.byType(AppBar, skipOffstage: false),
    );
    final icon = find.descendant(
      of: appBar,
      matching: find.byType(IconButton, skipOffstage: false),
    );
    await _until(
      tester,
      () =>
          _key('focus-remaining', offstage: true).evaluate().isEmpty &&
          icon.evaluate().length == 1,
    );
    tester.widget<IconButton>(icon).onPressed?.call();
    await tester.pump();
    expect(foreign.isCurrent, isTrue);
    expect(find.text('synthetic covered Back fallback'), findsOneWidget);
    navigation.currentState!.pop();
    await _until(tester, () => _timerRouteReady(tester));
    await _leave(tester, back: true);
    expect(find.byType(FocusTimerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in [false, true]) {
    for (final cover in ['foreign-return', 'background-return']) {
      testWidgets(
        'owner invalid=$invalid old exits stay retired after $cover',
        (tester) async {
          final owners = _owners();
          final navigation = GlobalKey<NavigatorState>();
          await _mount(
            tester,
            navigation: navigation,
            home: _launcher(navigation, () => _screen(owners.stream, _Clock())),
          );
          await _tap(tester, 'open-focus');
          await _until(tester, () => _timerRouteReady(tester));
          if (invalid) {
            owners.add(null);
            await tester.pump();
          }
          await _reveal(tester, _key('focus-untimed'));
          await _until(tester, () => _enabled(tester, 'focus-untimed'));
          final route = ModalRoute.of(
            tester.element(find.byType(FocusTimerScreen)),
          )!;
          final untimed = _action(tester, 'focus-untimed');
          final back = tester
              .widget<BackButton>(find.byType(BackButton))
              .onPressed!;
          if (cover == 'foreign-return') {
            await _cover(tester, navigation, 'synthetic pending-owner cover');
            navigation.currentState!.pop();
          } else {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          await _until(
            tester,
            () => _timerRouteReady(tester) && _enabled(tester, 'focus-untimed'),
          );
          untimed();
          back();
          await tester.pump();
          expect(route.isCurrent, isTrue);
          expect(find.byType(FocusTimerScreen), findsOneWidget);
          expect(_key('focus-minutes'), findsNothing);
          await _leave(tester);
          expect(find.byType(FocusTimerScreen), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('disposing a running timer retires its retained controls', (
    tester,
  ) async {
    final owners = _owners();
    final clock = _Clock();
    await _open(tester, owners, clock);
    await _tap(tester, 'focus-start');
    final stop = _action(tester, 'focus-stop');
    final finish = _action(tester, 'focus-finish');
    await tester.pumpWidget(const SizedBox.shrink());
    clock.advance(const Duration(days: 1));
    stop();
    finish();
    owners.add(null);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(FocusTimerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard Enter, Space and Tab operate labelled controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final owners = _owners();
      await _open(tester, owners, _Clock(), reducedMotion: true);
      await _reveal(tester, _key('focus-start'));
      _focusButton(tester, 'focus-start');
      await tester.pump();
      expect(
        tester
            .getSemantics(_key('focus-start'))
            .getSemanticsData()
            .label
            .trim(),
        isNotEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _until(tester, () => _enabled(tester, 'focus-pause'));
      await _reveal(tester, _key('focus-pause'));
      _focusButton(tester, 'focus-pause');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _until(tester, () => _enabled(tester, 'focus-resume'));
      await _reveal(tester, _key('focus-resume'));
      final resumeFocus = _focusButton(tester, 'focus-resume');
      await tester.pump();
      expect(resumeFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        identical(FocusManager.instance.primaryFocus, resumeFocus),
        isFalse,
      );
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      final live = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(
        find.ancestor(of: _key('focus-status'), matching: live),
        findsWidgets,
      );
      expect(
        find.ancestor(of: _key('focus-remaining'), matching: live),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final language in ['th', 'en']) {
    for (final layout in [
      'light-portrait',
      'dark-portrait',
      'dark-landscape',
    ]) {
      testWidgets(
        '$language $layout 200percent IME preserves reachable controls',
        (tester) async {
          final landscape = layout.endsWith('landscape');
          tester.view.physicalSize = landscape
              ? const Size(700, 320)
              : const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = FakeViewPadding(
            bottom: landscape ? 140 : 240,
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final owners = _owners();
          final clock = _Clock();
          final navigation = GlobalKey<NavigatorState>();
          await _mount(
            tester,
            navigation: navigation,
            home: _launcher(
              navigation,
              () => _screen(owners.stream, clock, language: language),
            ),
            scale: 2,
            dark: layout.startsWith('dark'),
            reducedMotion: true,
          );
          await _tap(tester, 'open-focus');
          await _until(tester, () => _timerRouteReady(tester));
          owners.add(_owner);
          await tester.pump();
          await _reveal(tester, _key('focus-remaining'));
          expect(_remaining(tester), '25:00');
          await _configure(tester, '0');
          expect(_field(tester).decoration?.errorText, isNotEmpty);
          await _reveal(tester, _key('focus-minutes'));
          final error = _field(tester).decoration!.errorText!;
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(error))
                .didExceedMaxLines,
            isFalse,
          );
          await _configure(tester, '1');
          await _tap(tester, 'focus-start');
          clock.advance(const Duration(seconds: 1));
          await _tap(tester, 'focus-pause');
          await _reveal(tester, _key('focus-remaining'));
          expect(_remaining(tester), '00:59');
          await _tap(tester, 'focus-resume');
          await _tap(tester, 'focus-finish');
          await _reveal(tester, _key('focus-new-interval'));
          expect(_key('focus-new-interval').hitTestable(), findsOneWidget);
          await _reveal(tester, _key('focus-untimed'));
          expect(_key('focus-untimed').hitTestable(), findsOneWidget);
          await _leave(tester);
          expect(find.byType(FocusTimerScreen), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'real owner timer operations preserve all37 tables and ordinary learning',
    (tester) async {
      late final Zone ioZone;
      final h = (await tester.runAsync(() {
        ioZone = Zone.current;
        return ReviewCenterHarness.open();
      }))!;
      final clock = _Clock();
      final navigation = GlobalKey<NavigatorState>();
      StreamSubscription<String?>? observation;
      final observed = <String?>[];
      try {
        await tester.runAsync(() async {
          observation = ioZone.run(() => h.ownerChanges.listen(observed.add));
        });
        final before = (await tester.runAsync(h.snapshotAllTables))!;
        expect(before, hasLength(37));
        await _mount(
          tester,
          navigation: navigation,
          home: _launcher(
            navigation,
            () => FocusTimerScreen(
              expectedOwnerId: configuredOwnerId,
              ownerChanges: h.ownerChanges,
              monotonicMicros: clock.read,
              languageCode: 'en',
            ),
          ),
        );
        await _tap(tester, 'open-focus');
        await _untilIo(tester, () => _enabled(tester, 'focus-start'));
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _configure(tester, '1');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _tap(tester, 'focus-start');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        clock.advance(const Duration(seconds: 10));
        await _tap(tester, 'focus-pause');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        clock.advance(const Duration(hours: 1));
        await _tap(tester, 'focus-resume');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        clock.advance(const Duration(seconds: 5));
        await _tap(tester, 'focus-stop');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _tap(tester, 'focus-start');
        clock.advance(const Duration(seconds: 3));
        await _tap(tester, 'focus-finish');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _tap(tester, 'focus-new-interval');
        await _tap(tester, 'focus-start');
        clock.advance(const Duration(minutes: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(_remaining(tester), '00:00');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _leave(tester);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _tap(tester, 'open-focus');
        await _untilIo(tester, () => _enabled(tester, 'focus-start'));
        expect(_remaining(tester), '25:00');
        final retained = _action(tester, 'focus-start');
        observed.clear();
        await tester.runAsync(
          () => h.database.transaction(() async {
            await h.switchOwner(configuredOtherOwnerId);
            await h.switchOwner(configuredOwnerId);
          }),
        );
        await _untilIo(
          tester,
          () => observed.contains(null) && observed.last == configuredOwnerId,
        );
        retained();
        await tester.pump();
        _expectUnavailable(tester);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await _leave(tester);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        final ordinary = (await tester.runAsync(() async {
          final session = await h.learning.startShadowing(limit: 1);
          final word = session.questions.single.word;
          h.now = h.now.add(const Duration(seconds: 3));
          final recorded = await h.learning.recordAnswer(
            sessionId: session.id,
            wordId: word.id,
            promptMode: 'shadowing',
            isCorrect: true,
            responseTimeMs: 3000,
            attemptNumber: 1,
            attemptId: 'synthetic-focus-ordinary-control-answer',
            occurredAtUtc: h.now,
            evidenceContext: captureCurrentActivityEvidence(
              promptMode: 'shadowing',
              contentRevision: word.contentRevision,
            ),
          );
          h.now = h.now.add(const Duration(seconds: 1));
          final summary = await h.learning.finishSession(session.id);
          return (recorded, summary);
        }))!;
        expect(ordinary.$1.inserted, isTrue);
        expect(ordinary.$2.state, 'completed');
        expect(ordinary.$2.correctCount, 1);
        final afterLearning = (await tester.runAsync(h.snapshotAllTables))!;
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'srs_states',
          'points_ledger_entries',
        ]) {
          expect(afterLearning[table], hasLength(1), reason: table);
        }
        for (final table in before.keys.where(
          (name) => name.startsWith('research_') || name.startsWith('study_'),
        )) {
          expect(afterLearning[table], before[table], reason: table);
        }
        final ordinaryOutbox = afterLearning['outbox_operations']!
            .map((row) => jsonDecode(row) as Map<String, dynamic>)
            .toList();
        expect(ordinaryOutbox, isNotEmpty);
        expect(
          ordinaryOutbox.every(
            (row) =>
                row['owner_id'] == configuredOwnerId &&
                {
                  'attempt',
                  'srsState',
                  'achievementUnlock',
                }.contains(row['entity_type']),
          ),
          isTrue,
        );
        expect(
          ordinaryOutbox.any(
            (row) =>
                row['entity_type'] == 'attempt' &&
                row['entity_id'] == 'synthetic-focus-ordinary-control-answer',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() => Future<void>.value());
        await tester.pump();
        await tester.runAsync(() async {
          await ioZone.run(() async => observation?.cancel());
          await ioZone.run(h.close);
        });
      }
    },
  );
}

const _owner = 'synthetic-focus-owner-a';

final class _Clock {
  int micros = 0;
  int read() => micros;
  void advance(Duration duration) => micros += duration.inMicroseconds;
}

StreamController<String?> _owners() {
  final owners = StreamController<String?>.broadcast(sync: true);
  addTearDown(() async {
    if (!owners.isClosed) {
      await owners.close();
    }
  });
  return owners;
}

FocusTimerScreen _screen(
  Stream<String?> owners,
  _Clock clock, {
  String expectedOwner = _owner,
  String language = 'en',
}) => FocusTimerScreen(
  expectedOwnerId: expectedOwner,
  ownerChanges: owners,
  monotonicMicros: clock.read,
  languageCode: language,
);

Future<void> _open(
  WidgetTester tester,
  StreamController<String?> owners,
  _Clock clock, {
  GlobalKey<NavigatorState>? navigation,
  String language = 'en',
  double scale = 1,
  bool dark = false,
  bool reducedMotion = false,
}) async {
  await _mount(
    tester,
    home: _screen(owners.stream, clock, language: language),
    navigation: navigation,
    scale: scale,
    dark: dark,
    reducedMotion: reducedMotion,
  );
  owners.add(_owner);
  await tester.pump();
  await _reveal(tester, _key('focus-remaining'));
  expect(_remaining(tester), '25:00');
}

Future<void> _mount(
  WidgetTester tester, {
  required Widget home,
  GlobalKey<NavigatorState>? navigation,
  double scale = 1,
  bool dark = false,
  bool reducedMotion = false,
  Widget Function(Widget)? wrap,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final app = MaterialApp(
    navigatorKey: navigation,
    theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: child!,
    ),
    home: home,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(wrap?.call(app) ?? app);
  await tester.pump();
}

Widget _launcher(
  GlobalKey<NavigatorState> navigation,
  Widget Function() screen,
) => Scaffold(
  body: Center(
    child: FilledButton(
      key: const ValueKey('open-focus'),
      onPressed: () => unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute<void>(builder: (_) => screen()),
        ),
      ),
      child: const Text('Open focus tool'),
    ),
  ),
);

Finder _key(String key, {bool offstage = false}) =>
    find.byKey(ValueKey(key), skipOffstage: !offstage);

String _remaining(WidgetTester tester) =>
    tester.widget<Text>(_key('focus-remaining')).data!;

String _status(WidgetTester tester) =>
    tester.widget<Text>(_key('focus-status')).data!;

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(_key('focus-minutes'));

bool _enabled(WidgetTester tester, String key) {
  final target = _key(key);
  return target.evaluate().isNotEmpty &&
      tester.widget<ButtonStyleButton>(target).onPressed != null;
}

VoidCallback _action(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed!;

void _expectUnavailable(WidgetTester tester) {
  expect(_key('focus-minutes', offstage: true), findsNothing);
  expect(_key('focus-remaining', offstage: true), findsNothing);
  expect(_enabled(tester, 'focus-start'), isFalse);
  expect(_enabled(tester, 'focus-resume'), isFalse);
  expect(_key('focus-untimed'), findsOneWidget);
}

Future<void> _configure(WidgetTester tester, String value) async {
  await _reveal(tester, _key('focus-minutes'));
  await tester.enterText(_key('focus-minutes'), value);
  await _tap(tester, 'focus-configure');
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.pumpAndSettle();
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(FocusTimerScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: scrollable,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await _reveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pump();
}

FocusNode _focusButton(WidgetTester tester, String key) {
  final label = find
      .descendant(of: _key(key), matching: find.byType(Text))
      .first;
  final focus = Focus.of(tester.element(label));
  focus.requestFocus();
  return focus;
}

Future<void> _leave(WidgetTester tester, {bool back = false}) async {
  final route = ModalRoute.of(tester.element(find.byType(FocusTimerScreen)))!;
  await _until(tester, () => _timerRouteReady(tester));
  if (back) {
    await _until(tester, () {
      final target = find.byType(BackButton).hitTestable();
      return target.evaluate().length == 1 &&
          tester.widget<BackButton>(target).onPressed != null;
    });
    await tester.tap(find.byType(BackButton).hitTestable());
    await tester.pump();
  } else {
    await _reveal(tester, _key('focus-untimed'));
    await _until(tester, () => _enabled(tester, 'focus-untimed'));
    await tester.tap(_key('focus-untimed').hitTestable());
    await tester.pump();
  }
  await _until(tester, () {
    if (route.navigator != null ||
        find
            .byType(FocusTimerScreen, skipOffstage: false)
            .evaluate()
            .isNotEmpty) {
      return false;
    }
    final launcher = _key('open-focus').hitTestable();
    if (launcher.evaluate().length != 1) {
      return false;
    }
    final parent = ModalRoute.of(tester.element(launcher));
    return parent?.isCurrent == true &&
        parent?.animation?.status == AnimationStatus.completed;
  });
}

bool _timerRouteReady(WidgetTester tester) {
  final timer = find.byType(FocusTimerScreen);
  if (timer.evaluate().isEmpty) {
    return false;
  }
  final route = ModalRoute.of(tester.element(timer));
  return route?.isCurrent == true &&
      route?.animation?.status == AnimationStatus.completed;
}

Future<MaterialPageRoute<void>> _cover(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigation,
  String label,
) async {
  final route = MaterialPageRoute<void>(
    builder: (_) => Scaffold(body: Text(label)),
  );
  unawaited(navigation.currentState!.push<void>(route));
  await _until(
    tester,
    () =>
        route.isCurrent && route.animation?.status == AnimationStatus.completed,
  );
  return route;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) {
      return;
    }
  }
  fail('The observable Focus Timer condition did not become true');
}

Future<void> _untilIo(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) {
      return;
    }
  }
  fail('The actual owner stream did not reach the expected Focus Timer state');
}

AppDependencies _dependencies() => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _Guest(),
);

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async => throw StateError(
    'Synthetic timer fixtures must not start a guest session',
  );
}
