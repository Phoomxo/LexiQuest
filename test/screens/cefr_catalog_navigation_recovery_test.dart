import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_catalog_screen.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_detail_screen.dart';

final _catalog = CefrVocabularyCatalog.fromBytes(
  File(CefrVocabularyCatalog.asset).readAsBytesSync(),
);
final _search = find.byKey(const ValueKey('cefr-catalog-search'));
Future<VoidCallback> _entry(WidgetTester tester) async {
  await tester.enterText(_search, 'about');
  await tester.pumpAndSettle();
  final tile = find.byKey(const ValueKey('cefr-word-cefrj15:about'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  expect(tile.hitTestable(), findsOneWidget);
  return tester.widget<ListTile>(tile).onTap!;
}

Future<ByteData?> _assetBytes(ByteData? message) async {
  final key = String.fromCharCodes(message!.buffer.asUint8List());
  final file = File(key);
  return file.existsSync()
      ? ByteData.sublistView(file.readAsBytesSync())
      : null;
}

void main() {
  for (final retirement in ['cover', 'lifecycle']) {
    testWidgets('AT detached license close retires after $retirement', (
      tester,
    ) async {
      rootBundle.clear();
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        _assetBytes,
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: CefrVocabularyCatalogScreen(catalog: Future.value(_catalog)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.info_outline));
      await tester.pumpAndSettle();
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'ปิด'))
          .onPressed!;
      if (retirement == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      close();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final current = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'ปิด'))
          .onPressed!;
      current();
      current();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_search, findsOneWidget);
      expect(tester.takeException(), isNull);
      rootBundle.clear();
    });
  }

  for (final failure in ['synchronous', 'immediate', 'delayed']) {
    testWidgets('AT $failure read retries same loader once and recovers', (
      tester,
    ) async {
      var reads = 0;
      final first = Completer<CefrVocabularyCatalog>();
      final retry = Completer<CefrVocabularyCatalog>();
      Future<CefrVocabularyCatalog> load() {
        reads++;
        if (reads > 1) return retry.future;
        if (failure == 'synchronous') throw StateError('read unavailable');
        if (failure == 'immediate')
          return Future.error(StateError('read unavailable'));
        return first.future;
      }

      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CefrVocabularyCatalogScreen(catalogLoader: load),
        ),
      );
      if (failure == 'delayed')
        first.completeError(StateError('read unavailable'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(TextButton, 'ลองใหม่');
      expect(button.hitTestable(), findsOneWidget);
      final again = tester.widget<TextButton>(button).onPressed!;
      again();
      again();
      await tester.pump();
      expect(reads, 2);
      retry.complete(_catalog);
      await tester.pumpAndSettle();
      expect(_search, findsOneWidget);
      expect(reads, 2);
      expect(tester.takeException(), isNull);
      again();
      await tester.pump();
      expect(reads, 2);
    });
  }

  for (final retirement in ['tab', 'cover', 'lifecycle', 'dispose']) {
    testWidgets('AT pending licenses retire on $retirement', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      final pending = Completer<ByteData?>();
      var reads = 0;
      const asset = 'assets/content/cefr_editorial/NOTICE.txt';
      rootBundle.clear();
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (message) async {
          final key = String.fromCharCodes(message!.buffer.asUint8List());
          if (key == asset) {
            reads++;
            return pending.future;
          }
          final bytes = File(key).readAsBytesSync();
          return ByteData.sublistView(bytes);
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          _assetBytes,
        );
        rootBundle.clear();
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, on, _) => TickerMode(
              enabled: on,
              child: CefrVocabularyCatalogScreen(
                catalog: Future.value(_catalog),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.info_outline));
      await tester.pump();
      expect(reads, 1);
      switch (retirement) {
        case 'tab':
          active.value = false;
          await tester.pump();
          active.value = true;
          await tester.pump();
        case 'cover':
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
          nav.currentState!.pop();
          await tester.pumpAndSettle();
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      pending.complete(ByteData.sublistView(File(asset).readAsBytesSync()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AT replacing pending catalog retires old read result', (
    tester,
  ) async {
    final old = Completer<CefrVocabularyCatalog>();
    await tester.pumpWidget(
      MaterialApp(home: CefrVocabularyCatalogScreen(catalog: old.future)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CefrVocabularyCatalogScreen(catalog: Future.value(_catalog)),
      ),
    );
    await tester.pump();
    expect(_search, findsOneWidget);
    old.completeError(StateError('retired read'));
    await tester.pumpAndSettle();
    expect(_search, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'AT fixed injected failed source retry never borrows bundled catalog',
    (tester) async {
      final failed = Completer<CefrVocabularyCatalog>();
      await tester.pumpWidget(
        MaterialApp(home: CefrVocabularyCatalogScreen(catalog: failed.future)),
      );
      failed.completeError(StateError('failed custom source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('ยังเปิดคลังคำศัพท์ไม่ได้'), findsOneWidget);
      expect(_search, findsNothing);
    },
  );
  testWidgets(
    'AT repeated detail taps create one route and return to same query',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CefrVocabularyCatalogScreen(catalog: Future.value(_catalog)),
        ),
      );
      await tester.pumpAndSettle();
      final open = await _entry(tester);
      open();
      open();
      await tester.pumpAndSettle();
      expect(
        find.byType(CefrVocabularyDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_search, findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'about',
      );
    },
  );
  testWidgets('AT duplicate license requests admit one dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CefrVocabularyCatalogScreen(catalog: Future.value(_catalog)),
      ),
    );
    await tester.pumpAndSettle();
    final info = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.info_outline))
        .onPressed!;
    info();
    info();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
  });
  for (final retirement in [
    'tab',
    'cover',
    'lifecycle',
    'replacement',
    'dispose',
  ]) {
    testWidgets(
      'AT retired catalog search filter and entry after $retirement',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final active = ValueNotifier(true);
        final source = ValueNotifier(Future.value(_catalog));
        addTearDown(active.dispose);
        addTearDown(source.dispose);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: ValueListenableBuilder<Future<CefrVocabularyCatalog>>(
              valueListenable: source,
              builder: (_, future, _) => ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, enabled, _) => TickerMode(
                  enabled: enabled,
                  child: CefrVocabularyCatalogScreen(catalog: future),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final open = await _entry(tester);
        final query = tester.widget<TextField>(_search).onChanged!;
        final filter = tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .onChanged!;
        switch (retirement) {
          case 'tab':
            active.value = false;
            await tester.pump();
            active.value = true;
            await tester.pumpAndSettle();
          case 'cover':
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
            await tester.pumpAndSettle();
            nav.currentState!.pop();
            await tester.pumpAndSettle();
          case 'lifecycle':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpAndSettle();
          case 'replacement':
            source.value = Future.value(_catalog);
            await tester.pumpAndSettle();
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        query('not-a-real-word');
        filter('C2');
        open();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CefrVocabularyDetailScreen), findsNothing);
        if (retirement != 'dispose') {
          expect(
            tester
                .widget<DropdownButton<String>>(
                  find.byType(DropdownButton<String>),
                )
                .value,
            'ALL',
          );
          expect(
            find.byKey(const ValueKey('cefr-word-cefrj15:about')),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final retirement in [
    'cover',
    'tab',
    'lifecycle',
    'replacement',
    'pop',
  ]) {
    testWidgets(
      'AT detached detail selection cannot pop another route after $retirement',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final active = ValueNotifier(true);
        final allowed = ValueNotifier(true);
        addTearDown(active.dispose);
        addTearDown(allowed.dispose);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('origin')),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute<int>(
            builder: (_) => ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (_, visible, _) => TickerMode(
                enabled: visible,
                child: ValueListenableBuilder<bool>(
                  valueListenable: allowed,
                  builder: (_, canAdd, _) => CefrVocabularyDetailScreen(
                    word: _catalog.words.first,
                    canAdd: canAdd,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final choose = tester
            .widget<ListTile>(find.byType(ListTile).first)
            .onTap!;
        switch (retirement) {
          case 'cover':
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
            await tester.pumpAndSettle();
          case 'tab':
            active.value = false;
            await tester.pump();
            active.value = true;
            await tester.pump();
          case 'lifecycle':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
          case 'replacement':
            allowed.value = false;
            await tester.pump();
            allowed.value = true;
            await tester.pump();
          case 'pop':
            nav.currentState!.pop();
            await tester.pumpAndSettle();
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
            await tester.pumpAndSettle();
        }
        choose();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (retirement == 'cover' || retirement == 'pop') {
          expect(find.text('cover'), findsOneWidget);
        } else {
          expect(find.byType(CefrVocabularyDetailScreen), findsOneWidget);
        }
      },
    );
  }
}
