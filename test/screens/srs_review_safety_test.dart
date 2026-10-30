import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';

import '../support/srs_review_ui_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owned cards and autoplay wait for canonical start ACK', (
    tester,
  ) async {
    final (h, repository) = await _fixture(tester);
    final ack = _gate();
    repository.afterStart = () => ack.future;
    final voice = SrsUiVoice();
    await _open(tester, h, voice: voice);
    await _until(tester, () => repository.starts.length == 1);
    await _untilAsync(
      tester,
      () async => await h.storage.count('learning_sessions') == 1,
    );
    expect(find.byKey(const Key('srs-card')), findsNothing);
    expect(find.byKey(const Key('srs-listen')), findsNothing);
    expect(voice.requests, isEmpty);
    ack.complete();
    await _ready(tester);
    expect(voice.requests, hasLength(1));
    expect(voice.requests.single.text, await _spelling(tester, h, 0));
    expect(voice.requests.single.contentId, h.wordIds.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(voice.requests, hasLength(1));
    expect(repository.genericWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lost start ACK retries the original handle and autoplays once', (
    tester,
  ) async {
    final (h, repository) = await _fixture(tester);
    var first = true;
    repository.afterStart = () async {
      if (first) {
        first = false;
        throw StateError('synthetic lost start ACK');
      }
    };
    final voice = SrsUiVoice();
    await _open(tester, h, voice: voice);
    await _until(
      tester,
      () => find.byKey(const Key('srs-retry')).evaluate().isNotEmpty,
    );
    expect(voice.requests, isEmpty);
    expect(find.byKey(const Key('srs-card')), findsNothing);
    await _tap(tester, 'srs-retry');
    await _ready(tester);
    expect(repository.starts, hasLength(2));
    expect(identical(repository.starts[0], repository.starts[1]), isTrue);
    expect(await _count(tester, h, 'learning_sessions'), 1);
    expect(voice.requests, hasLength(1));
    await tester.runAsync(h.settleNotifications);
    expect(h.notifications, 1);
    expect(repository.genericWrites, 0);
  });

  testWidgets('owner null-to-same while preparing can never start a review', (
    tester,
  ) async {
    final (h, repository) = await _fixture(tester);
    final gate = _gate();
    repository.beforePrepare = () => gate.future;
    final owners = _owners();
    final voice = SrsUiVoice();
    final before = await tester.runAsync(h.storage.snapshot);
    await _open(tester, h, voice: voice, ownerChanges: owners.stream);
    owners.add(configuredOwnerId);
    await _until(tester, () => repository.preparations == 1);
    owners
      ..add(null)
      ..add(configuredOwnerId);
    await tester.pump();
    gate.complete();
    await _unavailable(tester);
    await _drain(tester);
    expect(repository.starts, isEmpty);
    expect(voice.requests, isEmpty);
    expect(await tester.runAsync(h.storage.snapshot), before);
    expect(tester.takeException(), isNull);
  });

  for (final transition in ['null-to-same', 'other-to-same', 'error', 'done']) {
    testWidgets(
      'accepted SRS $transition invalidates retained callbacks permanently',
      (tester) async {
        final (h, repository) = await _fixture(tester);
        final owners = _owners();
        final voice = SrsUiVoice();
        await _open(tester, h, voice: voice, ownerChanges: owners.stream);
        owners.add(configuredOwnerId);
        await _ready(tester);
        final oldFlip = tester
            .widget<TextButton>(find.byKey(const Key('srs-flip')))
            .onPressed!;
        await _tap(tester, 'srs-flip');
        final oldRate = tester
            .widget<FilledButton>(find.byKey(const Key('srs-got')))
            .onPressed!;
        final oldListen = tester
            .widget<IconButton>(find.byKey(const Key('srs-listen')))
            .onPressed!;
        final before = await tester.runAsync(h.storage.snapshot);
        switch (transition) {
          case 'null-to-same':
            owners
              ..add(null)
              ..add(configuredOwnerId);
          case 'other-to-same':
            owners
              ..add(configuredOtherOwnerId)
              ..add(configuredOwnerId);
          case 'error':
            owners.addError(StateError('synthetic owner unavailable'));
          case 'done':
            await owners.close();
        }
        oldFlip();
        oldRate();
        oldListen();
        await _unavailable(tester);
        await _drain(tester);
        expect(find.byKey(const Key('srs-spelling')), findsNothing);
        expect(find.byKey(const Key('srs-meaning')), findsNothing);
        expect(repository.ratings, isEmpty);
        expect(voice.requests, hasLength(1));
        expect(await tester.runAsync(h.storage.snapshot), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'SRS direct owner invalidation during a frame hides content safely',
    (tester) async {
      final (h, repository) = await _fixture(tester);
      final owners = _owners();
      var emitDuringFrame = false;
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      final screen = SrsFlashcardsScreen(
        learning: h.learning,
        expectedOwnerId: configuredOwnerId,
        ownerChanges: owners.stream,
        languageCode: 'en',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, _, child) => Column(
              children: [
                Expanded(child: screen),
                Builder(
                  builder: (_) {
                    if (emitDuringFrame) {
                      emitDuringFrame = false;
                      owners
                        ..add(null)
                        ..add(configuredOwnerId);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      owners.add(configuredOwnerId);
      await _ready(tester);
      final oldFlip = tester
          .widget<TextButton>(find.byKey(const Key('srs-flip')))
          .onPressed!;
      emitDuringFrame = true;
      rebuild.value++;
      await tester.pump();
      oldFlip();
      await _unavailable(tester);
      expect(repository.ratings, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained old-card Flip Rate Next and Listen cannot affect the next card',
    (tester) async {
      final (h, repository) = await _fixture(tester);
      final voice = SrsUiVoice();
      await _open(tester, h, voice: voice);
      await _ready(tester);
      final oldFlip = tester
          .widget<TextButton>(find.byKey(const Key('srs-flip')))
          .onPressed!;
      final oldListen = tester
          .widget<IconButton>(find.byKey(const Key('srs-listen')))
          .onPressed!;
      await _tap(tester, 'srs-flip');
      final oldRate = tester
          .widget<FilledButton>(find.byKey(const Key('srs-got')))
          .onPressed!;
      oldRate();
      await _saved(tester);
      final oldNext = tester
          .widget<FilledButton>(find.byKey(const Key('srs-next')))
          .onPressed!;
      await _tap(tester, 'srs-next');
      await _until(tester, () => find.text('2/2').evaluate().isNotEmpty);
      final before = await tester.runAsync(h.storage.snapshot);
      oldFlip();
      oldRate();
      oldNext();
      oldListen();
      await _drain(tester);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.byKey(const Key('srs-flip')), findsOneWidget);
      expect(find.byKey(const Key('srs-got')), findsNothing);
      expect(repository.ratings, hasLength(1));
      expect(voice.requests, hasLength(2));
      expect(voice.requests.last.text, await _spelling(tester, h, 1));
      expect(await tester.runAsync(h.storage.snapshot), before);
      expect(repository.genericWrites, 0);
    },
  );

  testWidgets(
    'source finish ACK alone returns canonical immutable result with one frozen end',
    (tester) async {
      final (h, repository) = await _fixture(tester, due: false);
      final ack = _gate();
      var first = true;
      repository.afterFinish = () async {
        if (first) {
          first = false;
          throw StateError('synthetic lost finish ACK');
        }
        await ack.future;
      };
      LearningSessionResult? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<LearningSessionResult>(
                      MaterialPageRoute(
                        builder: (_) => SrsFlashcardsScreen(
                          learning: h.learning,
                          expectedOwnerId: configuredOwnerId,
                          ownerChanges: _realOwnerStreams[h]!,
                          sourceWordIds: h.wordIds,
                          languageCode: 'en',
                        ),
                      ),
                    );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _ready(tester);
      await _tap(tester, 'srs-flip');
      await _tap(tester, 'srs-again');
      await _saved(tester);
      await _tap(tester, 'srs-next');
      await _until(tester, () => find.text('2/2').evaluate().isNotEmpty);
      await _tap(tester, 'srs-flip');
      await _tap(tester, 'srs-got');
      await _saved(tester);
      await _tap(tester, 'srs-next');
      await _until(
        tester,
        () => find.byKey(const Key('srs-retry')).evaluate().isNotEmpty,
      );
      expect(result, isNull);
      expect(returned, isFalse);
      final afterLost = await tester.runAsync(h.storage.snapshot);
      h.now = h.now.add(const Duration(minutes: 1));
      await _tap(tester, 'srs-retry');
      await _until(tester, () => repository.finishes.length == 2);
      expect(result, isNull);
      expect(returned, isFalse);
      expect(identical(repository.finishes[0], repository.finishes[1]), isTrue);
      expect(
        repository.finishes[1].endedAtUtc,
        repository.finishes[0].endedAtUtc,
      );
      ack.complete();
      await _until(tester, () => returned);
      expect(result, isNotNull);
      expect(result!.summary.id, repository.starts.single.id);
      expect(result!.summary.state, 'completed');
      expect(result!.summary.correctCount, 1);
      expect(result!.summary.wrongCount, 1);
      expect(result!.mistakeWordIds, [h.wordIds.first]);
      expect(
        () => result!.mistakeWordIds.add('synthetic-other'),
        throwsUnsupportedError,
      );
      expect(await tester.runAsync(h.storage.snapshot), afterLost);
      expect(repository.ratings, hasLength(2));
      expect(repository.genericWrites, 0);
      expect(
        (await tester.runAsync(h.storage.researchCounts))!.values,
        everyElement(0),
      );
    },
  );

  for (final reason in [
    'foreign-route',
    'hidden',
    'inactive',
    'learning-replaced',
  ]) {
    testWidgets('held rating ACK cannot revive SRS after $reason', (
      tester,
    ) async {
      final (h, repository) = await _fixture(tester);
      final ack = _gate();
      repository.afterRating = () => ack.future;
      final nav = GlobalKey<NavigatorState>();
      final changed = ValueNotifier<bool>(false);
      addTearDown(changed.dispose);
      final replaced = h.useCases();
      final owners = _realOwnerStreams[h]!;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: ValueListenableBuilder<bool>(
            valueListenable: changed,
            builder: (_, value, child) => Visibility(
              visible: !(value && reason == 'hidden'),
              maintainState: true,
              child: SrsFlashcardsScreen(
                learning: value && reason == 'learning-replaced'
                    ? replaced
                    : h.learning,
                expectedOwnerId: configuredOwnerId,
                ownerChanges: owners,
                languageCode: 'en',
              ),
            ),
          ),
        ),
      );
      await _ready(tester);
      await _tap(tester, 'srs-flip');
      await _tap(tester, 'srs-got');
      await _untilAsync(
        tester,
        () async => await h.storage.count('answer_attempts') == 1,
      );
      final before = await tester.runAsync(h.storage.snapshot);
      if (reason == 'foreign-route') {
        unawaited(
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('foreign')),
            ),
          ),
        );
      } else if (reason == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        changed.value = true;
      }
      await tester.pump();
      ack.complete();
      await _drain(tester);
      if (reason == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      if (reason == 'hidden') changed.value = false;
      if (reason == 'foreign-route') {
        expect(find.text('foreign'), findsOneWidget);
        expect(nav.currentState!.canPop(), isTrue);
        nav.currentState!.pop();
      }
      await _unavailable(tester);
      expect(find.byKey(const Key('srs-next')), findsNothing);
      expect(repository.finishes, isEmpty);
      expect(await tester.runAsync(h.storage.snapshot), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'preview snapshots all 23 rows and never creates learning or research facts',
    (tester) async {
      final (h, repository) = await _fixture(tester);
      final words = [
        for (var i = 0; i < 23; i++)
          {
            'word': 'synthetic-preview-$i',
            'translation': 'meaning-$i',
            'example': 'synthetic example $i',
          },
      ];
      final before = await tester.runAsync(h.storage.snapshot);
      final voice = SrsUiVoice();
      await _open(tester, h, voice: voice, preview: words);
      await _ready(tester);
      expect(find.byKey(const Key('srs-preview-label')), findsOneWidget);
      expect(find.text('1/23'), findsOneWidget);
      words[1]['word'] = 'mutated-external-preview';
      words.clear();
      for (var i = 0; i < 23; i++) {
        expect(find.text('synthetic-preview-$i'), findsOneWidget);
        expect(find.text('${i + 1}/23'), findsOneWidget);
        await _tap(tester, 'srs-flip');
        await _tap(tester, 'srs-got');
        await _saved(tester);
        if (i < 22) await _tap(tester, 'srs-next');
      }
      expect(find.text('mutated-external-preview'), findsNothing);
      expect(repository.preparations, 0);
      expect(repository.starts, isEmpty);
      expect(repository.ratings, isEmpty);
      expect(repository.finishes, isEmpty);
      expect(repository.genericWrites, 0);
      expect(voice.requests, hasLength(23));
      expect(voice.requests.last.contentId, 'preview:22');
      expect(await tester.runAsync(h.storage.snapshot), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Replay joins an owned pending Stop and late old-card callbacks cannot restart audio',
    (tester) async {
      final (h, _) = await _fixture(tester);
      final voice = SrsUiVoice();
      await _open(tester, h, voice: voice);
      await _ready(tester);
      final oldListen = tester
          .widget<IconButton>(find.byKey(const Key('srs-listen')))
          .onPressed!;
      final stop = _gate();
      voice.holdStop = stop.future;
      await _tap(tester, 'srs-stop');
      oldListen();
      await tester.pump();
      expect(voice.requests, hasLength(1));
      expect(voice.stops, 1);
      stop.complete();
      await _until(tester, () => voice.requests.length == 2);
      await _tap(tester, 'srs-flip');
      await _tap(tester, 'srs-got');
      await _saved(tester);
      await _tap(tester, 'srs-next');
      await _until(tester, () => voice.requests.length == 3);
      oldListen();
      await _drain(tester);
      expect(voice.requests, hasLength(3));
      expect(voice.requests.last.contentId, h.wordIds[1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320 px 200 percent and IME keep self-rating and saved Next reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final (h, _) = await _fixture(tester);
      await _open(tester, h, scale: 2);
      await _ready(tester);
      await _tap(tester, 'srs-flip');
      await _tap(tester, 'srs-again');
      await _saved(tester);
      await _reveal(tester, find.byKey(const Key('srs-next')));
      expect(find.byKey(const Key('srs-next')).hitTestable(), findsOneWidget);
      expect(await _count(tester, h, 'answer_attempts'), 1);
      expect(tester.takeException(), isNull);
    },
  );
}

final _realOwnerStreams = Expando<Stream<String?>>();

Future<(SrsReviewHarness, SrsReviewUiRepository)> _fixture(
  WidgetTester tester, {
  bool due = true,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  late SrsReviewUiRepository repository;
  late Zone ioZone;
  final h = (await tester.runAsync(() {
    ioZone = Zone.current;
    return SrsReviewHarness.open(
      due: due,
      decorate: (delegate) => repository = SrsReviewUiRepository(delegate),
    );
  }))!;
  _realOwnerStreams[h] = srsRealIoStream(h.ownerChanges, ioZone: ioZone);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(h.close);
  });
  return (h, repository);
}

Completer<void> _gate() {
  final gate = Completer<void>();
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

StreamController<String?> _owners() {
  final owners = StreamController<String?>.broadcast(sync: true);
  addTearDown(() async {
    if (!owners.isClosed) await owners.close();
  });
  return owners;
}

Future<void> _open(
  WidgetTester tester,
  SrsReviewHarness h, {
  SrsUiVoice? voice,
  Stream<String?>? ownerChanges,
  List<Map<String, String>>? preview,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: SrsFlashcardsScreen(
      learning: h.learning,
      expectedOwnerId: configuredOwnerId,
      ownerChanges: ownerChanges ?? _realOwnerStreams[h]!,
      voice: voice == null ? null : VoiceUseCases(voice),
      wordList: preview,
      languageCode: 'en',
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 120; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (predicate()) return;
  }
  fail('SRS observable condition did not become true');
}

Future<void> _untilAsync(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if ((await tester.runAsync(predicate))!) return;
  }
  fail('SRS database condition did not become true');
}

Future<void> _ready(WidgetTester tester) => _until(tester, () {
  final card = find.byKey(const Key('srs-card'));
  if (card.evaluate().isEmpty) return false;
  final route = ModalRoute.of(tester.element(card));
  return route?.isCurrent == true &&
      (route?.animation?.status == AnimationStatus.completed ||
          route?.animation == null);
});

Future<void> _saved(WidgetTester tester) => _until(
  tester,
  () => find.byKey(const Key('srs-next')).evaluate().isNotEmpty,
);
Future<void> _unavailable(WidgetTester tester) => _until(
  tester,
  () => find.text('Activity unavailable').evaluate().isNotEmpty,
);

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.pump();
  final host = find.byType(SrsFlashcardsScreen);
  final outer = find
      .descendant(of: host, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: outer,
    maxScrolls: 40,
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pump();
  if (key == 'srs-flip') await tester.pumpAndSettle();
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<int> _count(
  WidgetTester tester,
  SrsReviewHarness h,
  String table,
) async => (await tester.runAsync(() => h.storage.count(table)))!;

Future<String> _spelling(
  WidgetTester tester,
  SrsReviewHarness h,
  int index,
) async => (await tester.runAsync(
  () async => (await (h.database.select(
    h.database.vocabularyWords,
  )..where((row) => row.id.equals(h.wordIds[index]))).getSingle()).spelling,
))!;
