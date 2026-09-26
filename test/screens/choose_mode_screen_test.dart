import 'package:vocab_learning_app/screens/cefr_vocabulary_catalog_screen.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_detail_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/learning_time_capture_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/local_reading_library_screen.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/matching_mode_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';
import '../support/r15_visual_capture.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';

Future<void> _scrollToModeEntry(WidgetTester tester, String entryId) async {
  final scrollable = find
      .descendant(
        of: find.byType(ChooseModeScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  var position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();

  final entry = find.byKey(ValueKey<String>(entryId));
  for (var step = 0; step < 64 && entry.evaluate().length != 1; step += 1) {
    position = tester.state<ScrollableState>(scrollable).position;
    final nextPixels = (position.pixels + 240)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextPixels == position.pixels) break;
    position.jumpTo(nextPixels);
    await tester.pump();
  }

  if (entry.evaluate().length != 1) {
    position = tester.state<ScrollableState>(scrollable).position;
    fail(
      'Choose Mode entry $entryId did not materialize exactly once; '
      'pixels=${position.pixels}, '
      'min=${position.minScrollExtent}, '
      'max=${position.maxScrollExtent}.',
    );
  }

  await tester.ensureVisible(entry);
  await tester.pump();
}

Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final context = tester.element(finder);
  ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
}

void _expectSingleThaiGlossaryAction({
  required Finder action,
  required String entryId,
}) {
  final entry = NavigationGlossary.require(entryId);
  final tooltip = find.descendant(
    of: action,
    matching: find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == entry.tooltip,
    ),
  );
  expect(tooltip, findsOneWidget);
  expect(
    find.descendant(of: tooltip, matching: find.text(entry.shortThaiLabel)),
    findsOneWidget,
  );
  final semanticActions = find
      .descendant(of: action, matching: find.byType(Semantics))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Semantics>()
      .where(
        (semantics) =>
            semantics.properties.label == entry.semanticsLabel &&
            semantics.properties.onTap != null &&
            semantics.excludeSemantics,
      )
      .toList(growable: false);
  expect(semanticActions, hasLength(1));
}

Future<void> _openConfiguredMode(
  WidgetTester tester,
  Finder modeEntry, {
  bool settleAfterStart = true,
  int? hintBudget,
  int? itemCount = 1,
  SessionDirection? direction,
  String? packLabel,
  int? timeLimitSeconds,
  bool untimed = false,
}) async {
  await tester.scrollUntilVisible(
    modeEntry,
    160,
    scrollable: find
        .descendant(
          of: find.byType(ChooseModeScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
  final opensReadingLibrary =
      tester.widget(modeEntry).key ==
      const ValueKey<String>('home/learn/reading/cefr');
  await tester.tap(modeEntry);
  await tester.pumpAndSettle();
  if (opensReadingLibrary) {
    expect(find.byType(LocalReadingLibraryScreen), findsOneWidget);
    final practice = find.text('ฝึกจากคำศัพท์ที่มีระดับ');
    await tester.scrollUntilVisible(practice, 200);
    await tester.pumpAndSettle();
    await tester.tap(practice);
    await tester.pumpAndSettle();
  }
  expect(find.byType(SessionConfigurationSheet), findsOneWidget);
  if (itemCount != null ||
      direction != null ||
      packLabel != null ||
      hintBudget != null ||
      timeLimitSeconds != null ||
      untimed) {
    await tester.tap(find.text('ปรับตัวเลือก'));
    await tester.pumpAndSettle();
  }
  if (itemCount != null) {
    await tester.enterText(
      find.byKey(const ValueKey('session-item-count')),
      '$itemCount',
    );
  }
  if (direction != null) {
    final directionField = find.byKey(const ValueKey('session-direction'));
    await tester.ensureVisible(directionField);
    await tester.tap(directionField);
    await tester.pumpAndSettle();
    final label = switch (direction) {
      SessionDirection.forward => 'ทิศทางปกติ',
      SessionDirection.reverse => 'ย้อนทิศทาง',
      SessionDirection.mixed => 'สลับทิศทาง',
    };
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }
  if (packLabel != null) {
    final packField = find.byKey(const ValueKey('session-pack'));
    await tester.ensureVisible(packField);
    await tester.tap(packField);
    await tester.pumpAndSettle();
    await tester.tap(find.text(packLabel).last);
    await tester.pumpAndSettle();
  }
  if (hintBudget != null) {
    final hintBudgetField = find.byKey(const ValueKey('session-hint-budget'));
    await tester.ensureVisible(hintBudgetField);
    await tester.tap(hintBudgetField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('$hintBudget').last);
    await tester.pumpAndSettle();
  }
  if (timeLimitSeconds != null) {
    await tester.enterText(
      find.byKey(const ValueKey('session-time-limit-seconds')),
      '$timeLimitSeconds',
    );
  }
  if (untimed) {
    final untimedOption = find.byKey(const ValueKey('session-timing-untimed'));
    await tester.ensureVisible(untimedOption);
    await tester.tap(untimedOption);
    await tester.pumpAndSettle();
  }
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final start = find.byKey(const ValueKey('session-config-start'));
  await tester.ensureVisible(start);
  await tester.pump();
  await tester.tap(start);
  if (settleAfterStart) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  for (final change in [
    'reading-off',
    'vocabulary-off',
    'replacement',
    'parent-removal',
  ]) {
    testWidgets('AT owned catalog detail live authority $change', (
      tester,
    ) async {
      final h = await _SrsGateHarness.create();
      addTearDown(h.close);
      final deps = ValueNotifier(h.dependencies);
      final parent = ValueNotifier(true);
      addTearDown(deps.dispose);
      addTearDown(parent.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<AppDependencies>(
          valueListenable: deps,
          builder: (_, d, _) => AppDependenciesScope(
            dependencies: d,
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: parent,
                builder: (_, show, _) => show
                    ? const CefrVocabularyCatalogScreen()
                    : const Scaffold(body: Text('original catalog parent')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cefr-catalog-search')),
        'about',
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('cefr-word-cefrj15:about'));
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(CefrVocabularyDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('add-curated-meaning')),
            )
            .onPressed,
        isNotNull,
      );
      switch (change) {
        case 'reading-off':
          h.features.emergencyOff(Feature.reading);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        case 'vocabulary-off':
          final retained = tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('add-curated-meaning')),
              )
              .onPressed!;
          h.features.emergencyOff(Feature.vocabulary);
          retained();
          await tester.pumpAndSettle();
          expect(find.byType(CefrVocabularyDetailScreen), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('add-curated-meaning')),
                )
                .onPressed,
            isNull,
          );
        case 'replacement':
          final replacement = await _SrsGateHarness.create();
          addTearDown(replacement.close);
          deps.value = replacement.dependencies;
          await tester.pumpAndSettle();
          h.features.emergencyOff(Feature.reading);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsNothing);
          replacement.features.emergencyOff(Feature.reading);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        case 'parent-removal':
          parent.value = false;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('about · A1'), findsOneWidget);
          h.features.emergencyOff(Feature.vocabulary);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('add-curated-meaning')),
                )
                .onPressed,
            isNull,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('original catalog parent'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'AS library immediate feature retirement rejects detached article push',
    (tester) async {
      final h = await _SrsGateHarness.create();
      addTearDown(h.close);
      await h.pump(tester);
      await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
      await tester.tap(find.byKey(const ValueKey('home/learn/reading/cefr')));
      await tester.pumpAndSettle();
      final open = tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'A1 · A book for May'),
          )
          .onTap!;
      final navigator = Navigator.of(
        tester.element(find.byType(LocalReadingLibraryScreen)),
      );
      h.features.emergencyOff(Feature.reading);
      open();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final retirement in [
    'tab',
    'cover',
    'lifecycle',
    'dispose',
    'replacement',
    'pop',
  ]) {
    testWidgets('AS chooser detached reading retires after $retirement', (
      tester,
    ) async {
      final nav = GlobalKey<NavigatorState>();
      final active = ValueNotifier(true);
      final version = ValueNotifier(0);
      addTearDown(active.dispose);
      addTearDown(version.dispose);
      Widget chooser() => ValueListenableBuilder<int>(
        valueListenable: version,
        builder: (_, v, _) => ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, on, _) => TickerMode(
            enabled: on,
            child: ChooseModeScreen(
              featureRegistry: BuildFeatureRegistry.allEnabled(),
              lessonModes: buildLessonModeRegistry(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: retirement == 'pop'
              ? const Scaffold(body: Text('root'))
              : chooser(),
        ),
      );
      if (retirement == 'pop') {
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => chooser()),
        );
        await tester.pumpAndSettle();
      }
      await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
      final dynamic entry = tester.widget(
        find.byKey(const ValueKey('home/learn/reading/cefr')),
      );
      final VoidCallback retained = entry.onTap;
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
        case 'replacement':
          version.value++;
          await tester.pump();
        case 'pop':
          nav.currentState!.pop();
      }
      retained();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ProductionFeatureGate), findsNothing);
    });
  }

  for (final child in ['library', 'article', 'catalog']) {
    testWidgets('AS $child rebinds replacement live registry', (tester) async {
      final h = await _SrsGateHarness.create();
      addTearDown(h.close);
      final replacement = await _SrsGateHarness.create();
      addTearDown(replacement.close);
      final deps = ValueNotifier(h.dependencies);
      addTearDown(deps.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<AppDependencies>(
          valueListenable: deps,
          builder: (_, d, _) => AppDependenciesScope(
            dependencies: d,
            child: const MaterialApp(home: ChooseModeScreen()),
          ),
        ),
      );
      await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
      await tester.tap(find.byKey(const ValueKey('home/learn/reading/cefr')));
      await tester.pumpAndSettle();
      if (child != 'library') {
        final target = child == 'article'
            ? find.text('A1 · A book for May')
            : find.byKey(const ValueKey('reading-library-vocabulary-catalog'));
        await tester.scrollUntilVisible(target, 200);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      deps.value = replacement.dependencies;
      await tester.pumpAndSettle();
      h.features.emergencyOff(Feature.reading);
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      replacement.features.emergencyOff(Feature.reading);
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('AS chooser repeated reading taps admit one library', (
    tester,
  ) async {
    final h = await _SrsGateHarness.create();
    addTearDown(h.close);
    await h.pump(tester);
    await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
    final entry = find.byKey(const ValueKey('home/learn/reading/cefr'));
    await tester.tap(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      find.byType(LocalReadingLibraryScreen, skipOffstage: false),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChooseModeScreen), findsOneWidget);
  });

  testWidgets('AS retained chooser reading action cannot stack libraries', (
    tester,
  ) async {
    final h = await _SrsGateHarness.create();
    addTearDown(h.close);
    await h.pump(tester);
    await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
    final dynamic entry = tester.widget(
      find.byKey(const ValueKey('home/learn/reading/cefr')),
    );
    entry.onTap();
    entry.onTap();
    await tester.pumpAndSettle();
    expect(
      find.byType(LocalReadingLibraryScreen, skipOffstage: false),
      findsOneWidget,
    );
  });

  for (final child in ['article', 'catalog']) {
    testWidgets('AS reading $child observes live emergency off', (
      tester,
    ) async {
      final h = await _SrsGateHarness.create();
      addTearDown(h.close);
      await h.pump(tester);
      await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
      await tester.tap(find.byKey(const ValueKey('home/learn/reading/cefr')));
      await tester.pumpAndSettle();
      final target = child == 'article'
          ? find.text('A1 · A book for May')
          : find.byKey(const ValueKey('reading-library-vocabulary-catalog'));
      await tester.scrollUntilVisible(target, 200);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      h.features.emergencyOff(Feature.reading);
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(CefrArticleReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('AS reading practice remains usable after chooser removal', (
    tester,
  ) async {
    final h = await _SrsGateHarness.create();
    addTearDown(h.close);
    final parent = ValueNotifier(true);
    addTearDown(parent.dispose);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: h.dependencies,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: parent,
            builder: (_, show, _) => show
                ? const ChooseModeScreen()
                : const Scaffold(body: Text('original parent')),
          ),
        ),
      ),
    );
    await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
    await tester.tap(find.byKey(const ValueKey('home/learn/reading/cefr')));
    await tester.pumpAndSettle();
    parent.value = false;
    await tester.pumpAndSettle();
    final target = find.text('ฝึกจากคำศัพท์ที่มีระดับ');
    await tester.scrollUntilVisible(target, 200);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SessionConfigurationSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final connection in ['absent', 'connected', 'disconnected']) {
    testWidgets('scratchpad MCP $connection preserves local-only input', (
      tester,
    ) async {
      final harness = await _SrsGateHarness.create(enableHandwriting: true);
      addTearDown(harness.close);
      final owner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      String? aiOwner = owner.id;
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      Future<String> snapshot() async => jsonEncode({
        for (final table in harness.database.allTables)
          table.actualTableName: [
            for (final row
                in await harness.database
                    .customSelect('SELECT * FROM "${table.actualTableName}"')
                    .get())
              row.data,
          ],
      });
      final before = await snapshot();
      final app = AppDependenciesScope(
        dependencies: harness.dependencies,
        child: MaterialApp(home: HandwritingScratchpadRoute(ownerId: owner.id)),
      );
      await tester.pumpWidget(
        connection == 'absent'
            ? app
            : MenuActionScope(registry: registry, child: app),
      );
      await tester.pumpAndSettle();
      final originalState = tester.state(find.byType(HandwritingScratchpad));
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'private scratch answer');
      final controller = tester
          .widget<HandwritingScratchpad>(find.byType(HandwritingScratchpad))
          .controller!;
      controller.beginStroke(const Offset(10, 10));
      controller.appendPoint(const Offset(20, 20));
      await tester.pump();
      if (connection == 'disconnected') {
        aiOwner = null;
        registry.invalidateSession(preserveContext: true);
        expect(registry.snapshot()['context'], isEmpty);
      }
      await tester.ensureVisible(find.text('ตรวจด้วยตัวเองแล้ว'));
      await tester.tap(find.text('ตรวจด้วยตัวเองแล้ว'));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(HandwritingScratchpad)),
        same(originalState),
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        'private scratch answer',
      );
      expect(controller.strokeCount, 1);
      expect(await snapshot(), before);
      if (connection == 'disconnected') aiOwner = owner.id;
      if (connection != 'absent') {
        final entries = registry.snapshot()['context'] as List;
        final selected = entries
            .where((dynamic e) => e['id'] == 'writing/scratchpad-assistance')
            .toList();
        expect(selected, hasLength(1));
        final data = jsonDecode(selected.single['value'] as String) as Map;
        expect(data['mode'], 'handwriting-scratchpad');
        expect(data['automaticHandwritingAssessment'], false);
        expect(data['writesProgressOrRewards'], false);
        expect(
          registry.snapshot().toString(),
          isNot(contains('private scratch answer')),
        );
        aiOwner = 'other-owner';
        expect(registry.snapshot()['context'], isEmpty);
      }
      expect(registry.snapshot()['actions'], isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controller.strokeCount, 0);
    });
  }

  testWidgets('A-UI-08 Choose bounds and bottom system inset', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      const MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: BuildFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('learning-menu-scroll'))).width,
      lessThanOrEqualTo(960),
    );
    await _scrollToModeEntry(tester, 'home/learn/quiz/cloze');
    expect(
      tester
          .getRect(find.byKey(const ValueKey('home/learn/quiz/cloze')))
          .bottom,
      lessThanOrEqualTo(750),
    );
  });
  setUpAll(loadR15Fonts);
  for (final width in [320.0, 390.0, 840.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('visual Choose w$width s$scale dark$dark', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('synthetic-r15-surface'),
              child: MaterialApp(
                theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const ChooseModeScreen(
                  featureRegistry: BuildFeatureRegistry.allEnabled(),
                ),
              ),
            ),
          );
          await captureR15Surface(
            tester,
            'A-UI-01-T02-mode-w${width.toInt()}-s${scale.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await _scrollToModeEntry(tester, 'home/learn/quiz/cloze');
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('home/learn/quiz/cloze')).hitTestable(),
            findsOneWidget,
          );
        });
      }
    }
  }

  for (final scenario in [
    (320.0, 1.0, 1),
    (390.0, 1.0, 2),
    (840.0, 1.0, 3),
    (840.0, 1.5, 1),
  ]) {
    testWidgets('A-UI-06 mode columns $scenario', (tester) async {
      tester.view.physicalSize = Size(scenario.$1, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.$2)),
            child: child!,
          ),
          home: const ChooseModeScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rects = [
        for (final id in [
          'home/learn/quiz',
          'home/learn/quiz/definition',
          'home/learn/srs',
        ])
          tester.getRect(find.byKey(ValueKey(id))),
      ];
      expect(
        rects.where((rect) => rect.top == rects.first.top).length,
        scenario.$3,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clear starter launches the existing configured meaning quiz', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create();
    addTearDown(harness.close);
    await harness.pump(tester);
    final starter = find.byKey(const ValueKey('learn-starter'));
    expect(starter, findsOneWidget);
    await _openConfiguredMode(
      tester,
      starter,
      itemCount: 1,
      direction: SessionDirection.reverse,
    );
    expect(find.byType(QuizScreen), findsOneWidget);
    final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
    expect(screen.sessionConfiguration?.itemCount, 1);
    expect(screen.sessionConfiguration?.direction, SessionDirection.reverse);
    expect(harness.controllers.single.state.itemCount, 1);
  });
  testWidgets(
    'menu cards stay separated on a narrow screen with large Thai text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
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
          home: const ChooseModeScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
      await _scrollToModeEntry(tester, 'home/learn/quiz');
      await tester.drag(
        find.byKey(const ValueKey('learning-menu-scroll')),
        const Offset(0, -160),
      );
      await tester.pump();
      final cards = find.byType(Card);
      final first = tester.getRect(
        find.descendant(of: cards.at(0), matching: find.byType(Material)).first,
      );
      final second = tester.getRect(
        find.descendant(of: cards.at(1), matching: find.byType(Material)).first,
      );
      expect(second.top - first.bottom, greaterThanOrEqualTo(12));
      await _scrollToModeEntry(tester, 'home/learn/associative-reading');
      expect(
        find.byKey(const ValueKey('home/learn/associative-reading')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'f16 validated count and reverse direction govern delivered meaning quiz',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableQuizDistractor: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
        direction: SessionDirection.reverse,
      );

      final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(screen.sessionConfiguration?.itemCount, 1);
      expect(screen.sessionConfiguration?.direction, SessionDirection.reverse);
      expect(find.text('lasting'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:srs-gate-vocabulary-durable',
          ),
        ),
        findsOneWidget,
      );
      expect(harness.controllers.single.state.itemCount, 1);
    },
  );

  testWidgets('f16 exact pinned pack revision governs delivered vocabulary', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      enableQuizDistractor: true,
      pinnedPack: _testPinnedPack(),
    );
    addTearDown(harness.close);
    await harness.pump(tester);

    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
      packLabel: 'Pinned f16 pack revision 3',
    );

    final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
    expect(screen.sessionConfiguration?.packIdentity, _testPackIdentity);
    expect(harness.controllers.single.state.itemCount, 1);
    expect(find.text('durable'), findsWidgets);
  });

  testWidgets('f16 pinned pack content drift renders a typed reset prompt', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      pinnedPack: _testPinnedPack(
        vocabularyWordIds: const <String>['word:missing-from-owner-library'],
      ),
    );
    addTearDown(harness.close);
    await harness.pump(tester);

    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
      packLabel: 'Pinned f16 pack revision 3',
    );

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(find.text('ไม่พบชุดเนื้อหาการเรียนรุ่นที่เลือกไว้'), findsOneWidget);
    expect(
      harness.controllers.single.state.status,
      LessonSessionStatus.planned,
    );
  });

  testWidgets('f16 production Choose path renders stale stored reset prompt', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create();
    addTearDown(harness.close);
    final owner = await harness.dependencies.localOwners!
        .getOrCreateActiveOwner();
    final registration = harness.dependencies.lessonModes!.resolve(
      LessonMode.meaningQuiz,
    )!;
    const currentLimits = SessionConfigurationProtocolLimits.standard();
    final staleLimits = currentLimits.copyWith(protocolVersion: 'stale');
    const policy = SessionConfigurationPolicy();
    final stale = policy.validate(
      draft: policy
          .defaultsFor(registration: registration, limits: staleLimits)
          .copyWith(itemCount: 1),
      registration: registration,
      limits: staleLimits,
      ownerId: owner.id,
      availablePackIdentities: const <ContentIdentity>[],
    );
    await harness.sessionConfigurations.save(
      stale,
      updatedAtUtc: DateTime.utc(2026, 8, 26),
    );
    await harness.pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text('ขอบเขตการเรียนเปลี่ยนไปหลังจากตั้งค่ากิจกรรมนี้'),
      findsOneWidget,
    );
  });

  testWidgets('f16 persisted protocol drift opens typed reset sheet', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(staleProtocol: true);
    addTearDown(harness.close);
    await harness.pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text('ขอบเขตการเรียนเปลี่ยนไปหลังจากตั้งค่ากิจกรรมนี้'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('session-config-reset')));
    await tester.pumpAndSettle();

    expect(find.byType(SessionConfigurationSheet), findsNothing);
    expect(find.byType(ChooseModeScreen), findsOneWidget);
    expect(harness.controllers, isEmpty);
  });

  testWidgets(
    'f16 opens one validated configuration sheet before route construction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      final tile = find.byKey(const ValueKey<String>('home/learn/quiz'));
      final dynamic configuredTile = tester.widget(tile);
      configuredTile.onTap();
      configuredTile.onTap();
      await tester.pumpAndSettle();

      expect(find.byType(SessionConfigurationSheet), findsOneWidget);
      expect(find.byType(ProductionFeatureGate), findsNothing);
      expect(find.byType(UnifiedLessonShell), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(find.byType(SessionConfigurationSheet), findsNothing);
      expect(find.byType(ProductionFeatureGate), findsOneWidget);
    },
  );

  testWidgets(
    'f16 emergency-off between validation and start prevents navigation',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: features,
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionConfigurationSheet), findsOneWidget);

      features.emergencyOff(Feature.quiz);
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(find.byType(UnifiedLessonShell), findsNothing);
      expect(
        find.text('This lesson mode is no longer available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('f16 a retained live-off mode callback cannot configure', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(features.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: features,
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );
    final tile = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('home/learn/quiz')),
        matching: find.byType(InkWell),
      ),
    );
    final retainedOpen = tile.onTap!;

    features.emergencyOff(Feature.quiz);
    retainedOpen();
    await tester.pumpAndSettle();

    expect(find.byType(SessionConfigurationSheet), findsNothing);
    expect(find.byType(UnifiedLessonShell), findsNothing);
    expect(find.text('โหมดการเรียนนี้ไม่พร้อมใช้งานแล้ว'), findsOneWidget);
  });

  testWidgets('B06 scratchpad direct route fails closed when not delivered', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create();
    addTearDown(harness.close);
    final owner = await harness.dependencies.localOwners!
        .getOrCreateActiveOwner();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: harness.dependencies,
        child: MaterialApp(home: HandwritingScratchpadRoute(ownerId: owner.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HandwritingScratchpad), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final retire in ['exit', 'owner', 'emergency']) {
    testWidgets('B06 scratchpad route $retire clears without durable mutations', (
      tester,
    ) async {
      final harness = await _SrsGateHarness.create(enableHandwriting: true);
      addTearDown(harness.close);
      Future<List<String>> snapshot() async => [
        for (final table in harness.database.allTables)
          if (table.actualTableName != 'local_owners')
            '${table.actualTableName}:${await harness.database.customSelect('SELECT * FROM "${table.actualTableName}"').get().then((rows) => rows.map((r) => r.data).toList())}',
      ];
      final before = await snapshot();
      await harness.pump(tester);
      await _scrollToModeEntry(tester, 'home/learn/handwriting-scratchpad');
      await tester.tap(
        find.byKey(const ValueKey('home/learn/handwriting-scratchpad')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionConfigurationSheet), findsNothing);
      expect(find.byType(HandwritingScratchpad), findsOneWidget);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'private scratch answer');
      await tester.ensureVisible(find.text('ตรวจด้วยตัวเองแล้ว'));
      await tester.tap(find.text('ตรวจด้วยตัวเองแล้ว'));
      await tester.pump();
      final controller = tester
          .widget<HandwritingScratchpad>(find.byType(HandwritingScratchpad))
          .controller!;
      controller.beginStroke(const Offset(10, 10));
      if (retire == 'exit') {
        Navigator.of(tester.element(find.byType(HandwritingScratchpad))).pop();
      } else if (retire == 'emergency') {
        harness.features.emergencyOff(Feature.quiz);
      } else {
        await harness.database.customStatement(
          'UPDATE local_owners SET is_active = 0',
        );
        harness.database.notifyUpdates({
          TableUpdate.onTable(harness.database.localOwners),
        });
      }
      await tester.pumpAndSettle();
      expect(find.byType(HandwritingScratchpad), findsNothing);
      expect(controller.strokeCount, 0);
      if (retire == 'emergency') {
        harness.features.clearOverride(Feature.quiz);
        await tester.pumpAndSettle();
        expect(find.byType(HandwritingScratchpad), findsNothing);
      }
      expect(find.text('private scratch answer'), findsNothing);
      expect(await snapshot(), before);
      expect(harness.controllers, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('f13 shows every registered production native mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );

    const entryIdsInCatalogOrder = <String>[
      'home/learn/associative-reading',
      'home/learn/reading/cefr',
      'home/learn/quiz/dictation',
      'home/learn/quiz/sentence-scramble',
      'home/learn/quiz/word-scramble',
      'home/learn/speech/speaking',
      'home/learn/speech/shadowing',
    ];
    for (final entryId in entryIdsInCatalogOrder) {
      await _scrollToModeEntry(tester, entryId);
      expect(
        find.byKey(ValueKey<String>(entryId)),
        findsOneWidget,
        reason: '$entryId must have one Choose Mode parent',
      );
    }
  });

  testWidgets('Thai glossary covers every registered Choose Mode tile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLessonModeRegistry(
              matchingDeliveryState: LessonModeDeliveryState.enabled,
            ),
          ),
        ),
      );

      const cases = <(String, String, IconData)>[
        (
          'home/learn/associative-reading',
          'อ่านเชื่อมโยงความจำ',
          Icons.auto_stories_outlined,
        ),
        ('home/learn/quiz', 'แบบทดสอบจากคลังคำศัพท์', Icons.quiz_outlined),
        (
          'home/learn/quiz/typed-recall',
          'นึกคำแล้วพิมพ์',
          Icons.keyboard_outlined,
        ),
        (
          'home/learn/quiz/matching',
          'จับคู่คำศัพท์',
          Icons.compare_arrows_outlined,
        ),
        ('home/learn/quiz/cloze', 'เติมคำในประโยค', Icons.space_bar_outlined),
        (
          'home/learn/quiz/definition',
          'เลือกคำจากคำอธิบาย',
          Icons.menu_book_outlined,
        ),
        ('home/learn/srs', 'ทบทวนคำศัพท์', Icons.event_repeat_outlined),
        (
          'home/learn/reading/cefr',
          'อ่านตามระดับภาษา CEFR',
          Icons.chrome_reader_mode_outlined,
        ),
        ('home/learn/quiz/dictation', 'ฟังแล้วพิมพ์', Icons.hearing_outlined),
        (
          'home/learn/quiz/sentence-scramble',
          'เรียงประโยค',
          Icons.format_list_numbered_outlined,
        ),
        (
          'home/learn/quiz/word-scramble',
          'เรียงตัวอักษร',
          Icons.extension_outlined,
        ),
        ('home/learn/speech/speaking', 'ฝึกออกเสียง', Icons.mic_outlined),
        (
          'home/learn/speech/shadowing',
          'ฝึกพูดตาม',
          Icons.record_voice_over_outlined,
        ),
      ];
      for (final (id, _, icon) in cases) {
        await _scrollToModeEntry(tester, id);
        final tile = find.byKey(ValueKey<String>(id));
        expect(tile, findsOneWidget);
        expect(
          find.descendant(
            of: tile,
            matching: find.text(NavigationGlossary.require(id).shortThaiLabel),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tile, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        _expectSingleThaiGlossaryAction(action: tile, entryId: id);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Thai SRS semantics stays attached to its stable mode key', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _SrsGateHarness.create();
    addTearDown(harness.close);
    try {
      await harness.pump(tester);

      await _scrollToModeEntry(tester, 'home/learn/srs');
      final entry = find.byKey(const ValueKey<String>('home/learn/srs'));
      expect(entry, findsOneWidget);
      expect(
        find.descendant(
          of: entry,
          matching: find.bySemanticsLabel('เปิดทบทวนคำศัพท์'),
        ),
        findsOneWidget,
      );

      await _openConfiguredMode(tester, entry, itemCount: 1);
      final screen = find.byType(SrsFlashcardsScreen);
      expect(screen, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(screen))?.settings.name,
        'learning/srs',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('f13 speaking tile is reachable in the lazy catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );

    await _scrollToModeEntry(tester, 'home/learn/speech/speaking');
    expect(
      find.byKey(const ValueKey<String>('home/learn/speech/speaking')),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows only canonical production modes and does not navigate without an adapter',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );

      for (final id in [
        'home/learn/quiz',
        'home/learn/srs',
        'home/learn/quiz/definition',
        'home/learn/associative-reading',
        'home/learn/quiz/cloze',
      ]) {
        await _scrollToModeEntry(tester, id);
        expect(find.byKey(ValueKey(id)), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('learn-starter')),
        findsNothing,
        reason: 'No configured starter without a learning adapter',
      );
      expect(
        find.byKey(const ValueKey('home/learn/quiz/typed-recall')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home/learn/quiz/matching')),
        findsNothing,
      );
      await _scrollToModeEntry(tester, 'home/learn/quiz');

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(ChooseModeScreen))).canPop(),
        isFalse,
      );
    },
  );

  testWidgets(
    'resolved mode always enters through the fail-closed feature gate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
      );

      expect(find.byType(ProductionFeatureGate), findsOneWidget);
      final unavailable = tester.widget<ProductionFeatureUnavailable>(
        find.byType(ProductionFeatureUnavailable),
      );
      expect(
        unavailable.reason,
        ProductionFeatureUnavailableReason.missingDependency,
      );
    },
  );

  testWidgets(
    'every production mode reaches one controller-backed shell on its stable route',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 24, 12);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'choose-mode-owner',
        nowUtc: () => now,
      );
      var learningId = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'choose-mode-id-${++learningId}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f05-choose-mode-test',
        ),
      );
      var vocabularyId = 0;
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => vocabularyId++ < 2
            ? 'choose-mode-vocabulary-id'
            : 'choose-mode-vocabulary-id-two',
        nowUtc: () => now,
      );
      await owners.getOrCreateActiveOwner();
      final category = await vocabulary.createCategory('Reading');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'durable',
          meaning: 'able to last',
          partOfSpeech: 'adjective',
          cefrLevel: 'C2',
        ),
      );
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'stable',
          meaning: 'not likely to change',
          partOfSpeech: 'adjective',
          cefrLevel: 'C2',
        ),
      );
      final modes = buildLessonModeRegistry(
        matchingDeliveryState: LessonModeDeliveryState.enabled,
      );
      final research = InertResearchDependencies(database);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      var controllerBuilds = 0;
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _GuestSession(),
        quest: testQuestUseCases(),
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
        learning: learning,
        vocabulary: vocabulary,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        speechPractice: SpeechPracticeUseCases(_InertSpeechGateway()),
        features: features,
        localOwners: owners,
        lessonModes: modes,
        sessionConfigurations: DriftSessionConfigurationStore(database),
        createLessonController: (adapter) {
          controllerBuilds += 1;
          return UnifiedLessonController(learning: learning, adapter: adapter);
        },
        associativeLearning: InMemoryAssociativeLearningAdapter(),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: const MaterialApp(home: ChooseModeScreen()),
        ),
      );

      const cases = <({String entryId, LessonMode mode, String routeName})>[
        (
          entryId: 'home/learn/associative-reading',
          mode: LessonMode.associativeReading,
          routeName: 'learning/associative-reading/session',
        ),
        (
          entryId: 'home/learn/quiz',
          mode: LessonMode.meaningQuiz,
          routeName: 'learning/quiz',
        ),
        (
          entryId: 'home/learn/quiz/typed-recall',
          mode: LessonMode.typedRecall,
          routeName: 'learning/typed-recall',
        ),
        (
          entryId: 'home/learn/quiz/matching',
          mode: LessonMode.matching,
          routeName: 'learning/matching',
        ),
        (
          entryId: 'home/learn/quiz/cloze',
          mode: LessonMode.cloze,
          routeName: 'learning/cloze',
        ),
        (
          entryId: 'home/learn/quiz/definition',
          mode: LessonMode.definitionQuiz,
          routeName: 'learning/definition-quiz',
        ),
        (
          entryId: 'home/learn/reading/cefr',
          mode: LessonMode.cefrReading,
          routeName: 'learning/cefr-reading',
        ),
        (
          entryId: 'home/learn/quiz/dictation',
          mode: LessonMode.dictation,
          routeName: 'game/dictation',
        ),
        (
          entryId: 'home/learn/quiz/sentence-scramble',
          mode: LessonMode.sentenceScramble,
          routeName: 'game/sentence-scramble',
        ),
        (
          entryId: 'home/learn/quiz/word-scramble',
          mode: LessonMode.wordScramble,
          routeName: 'game/word-scramble',
        ),
        (
          entryId: 'home/learn/speech/speaking',
          mode: LessonMode.speaking,
          routeName: 'practice/speaking',
        ),
        (
          entryId: 'home/learn/speech/shadowing',
          mode: LessonMode.shadowing,
          routeName: 'practice/shadowing',
        ),
        (
          entryId: 'home/learn/srs',
          mode: LessonMode.flashcard,
          routeName: 'learning/srs',
        ),
      ];
      for (final (index, routeCase) in cases.indexed) {
        await _scrollToModeEntry(tester, routeCase.entryId);
        final entry = find.byKey(ValueKey<String>(routeCase.entryId));
        await tester.pump();
        await _openConfiguredMode(
          tester,
          entry,
          itemCount: routeCase.mode == LessonMode.matching ? 2 : 1,
        );

        if (routeCase.mode == LessonMode.associativeReading) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isNot(isA<TypedRecallModeAdapter>()),
          );
          expect(controllerBuilds, 0);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          await tester.tap(find.text('เริ่มอ่าน'));
          await tester.pumpAndSettle();
        }

        expect(
          controllerBuilds,
          index + 1,
          reason: '${routeCase.mode.id} must create one controller',
        );
        expect(
          find.byType(UnifiedLessonShell),
          findsOneWidget,
          reason: '${routeCase.mode.id} must retain one shell',
        );
        final shell = tester.widget<UnifiedLessonShell>(
          find.byType(UnifiedLessonShell),
        );
        expect(
          ModalRoute.of(
            tester.element(find.byType(UnifiedLessonShell)),
          )?.settings.name,
          routeCase.routeName,
        );
        final controller = shell.controller!;
        expect(controller.state.mode, routeCase.mode);
        if (routeCase.mode == LessonMode.flashcard) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<FlashcardModeAdapter>(),
          );
          expect(
            tester
                .widget<SrsFlashcardsScreen>(find.byType(SrsFlashcardsScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
        }
        if (routeCase.mode == LessonMode.meaningQuiz) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<MeaningQuizModeAdapter>(),
          );
          expect(
            tester.widget<QuizScreen>(find.byType(QuizScreen)).modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(
            tester.widget<QuizScreen>(find.byType(QuizScreen)).typedRecall,
            isFalse,
          );
          expect(controller.state.status, LessonSessionStatus.active);

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.paused);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.typedRecall) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<TypedRecallModeAdapter>(),
          );
          final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
          expect(
            screen.typedRecallModeAdapter,
            same(modes.resolveTypedRecall()!.adapter),
          );
          expect(screen.typedRecall, isTrue);
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.definitionQuiz) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<DefinitionQuizModeAdapter>(),
          );
          expect(
            tester
                .widget<DefinitionQuizScreen>(find.byType(DefinitionQuizScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.cloze) {
          expect(modes.find(routeCase.mode)!.adapter, isA<ClozeModeAdapter>());
          expect(
            tester
                .widget<FillInTheBlanksScreen>(
                  find.byType(FillInTheBlanksScreen),
                )
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.matching) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<MatchingModeAdapter>(),
          );
          expect(
            tester
                .widget<MatchingModeScreen>(find.byType(MatchingModeScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.cefrReading) {
          final screen = tester.widget<CefrArticleReaderScreen>(
            find.byType(CefrArticleReaderScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.cefrLevel, 'C2');
          expect(screen.sessionId, controller.state.sessionId);
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(screen.wordId, startsWith('word:choose-mode-vocabulary-id'));
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.dictation) {
          final screen = tester.widget<DictationQuizScreen>(
            find.byType(DictationQuizScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.sentenceScramble) {
          // User-authored words without reviewed examples must not become
          // fabricated "word means translation" sentence exercises.
          expect(find.byType(SentenceScrambleScreen), findsNothing);
          expect(
            find.byKey(const ValueKey('sentence-example-unavailable')),
            findsOneWidget,
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.wordScramble) {
          final screen = tester.widget<WordScrambleScreen>(
            find.byType(WordScrambleScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.speaking) {
          final screen = tester.widget<SpeakToTextScreen>(
            find.byType(SpeakToTextScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.shadowing) {
          final screen = tester.widget<ShadowingChallengeScreen>(
            find.byType(ShadowingChallengeScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }

        if (const <LessonMode>{
          LessonMode.dictation,
          LessonMode.speaking,
          LessonMode.shadowing,
          LessonMode.cefrReading,
          LessonMode.sentenceScramble,
          LessonMode.wordScramble,
        }.contains(routeCase.mode)) {
          final parentFeature = modes.find(routeCase.mode)!.feature;
          features.emergencyOff(parentFeature);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          expect(
            controller.state.status,
            LessonSessionStatus.abandoned,
            reason:
                '${routeCase.mode.id} must reconcile when its parent turns off',
          );
          features.clearOverride(parentFeature);
          Navigator.of(
            tester.element(find.byType(ProductionFeatureUnavailable)),
          ).pop();
          await tester.pumpAndSettle();
          if (routeCase.mode == LessonMode.cefrReading) {
            expect(find.byType(LocalReadingLibraryScreen), findsOneWidget);
            Navigator.of(
              tester.element(find.byType(LocalReadingLibraryScreen)),
            ).pop();
            await tester.pumpAndSettle();
          }
          continue;
        }

        if (routeCase.mode == LessonMode.flashcard) {
          features.emergencyOff(Feature.srs);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
          expect(find.byType(SrsFlashcardsScreen), findsNothing);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          continue;
        }

        Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
        await tester.pumpAndSettle();
        if (routeCase.mode == LessonMode.associativeReading) {
          Navigator.of(tester.element(find.text('เริ่มอ่าน'))).pop();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'SRS off during delayed due load compensates the later durable session',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayDue: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        settleAfterStart: false,
      );
      await tester.runAsync(
        () => harness.repository.dueEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.srs);
      harness.repository.dueRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.abandoned,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets('unclassified CEFR word creates no durable vocabulary session', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(vocabularyCefrLevel: null);
    addTearDown(harness.close);
    await harness.pump(tester);

    await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/reading/cefr')),
    );

    expect(find.byType(CefrArticleReaderScreen), findsNothing);
    expect(
      find.text('ยังไม่มีคำศัพท์ที่เข้าเงื่อนไขของกิจกรรมนี้'),
      findsOneWidget,
    );
    expect(find.byType(UnifiedLessonShell), findsOneWidget);
    expect(
      harness.controllers.single.state.status,
      LessonSessionStatus.planned,
    );
    final sessions = await harness.database
        .select(harness.database.learningSessions)
        .get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(sessions, hasLength(1), reason: 'only the completed seed remains');
    expect(sessions.single.state, 'completed');
    expect(
      await harness.database.select(harness.database.answerAttempts).get(),
      hasLength(1),
    );
  });

  testWidgets(
    'canonical A2 through C2 CEFR routes preserve pinned word and session identity',
    (tester) async {
      for (final level in const <String>['A2', 'B1', 'B2', 'C1', 'C2']) {
        final harness = await _SrsGateHarness.create(
          vocabularyCefrLevel: level,
        );
        await harness.pump(tester);

        await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
        await _openConfiguredMode(
          tester,
          find.byKey(const ValueKey<String>('home/learn/reading/cefr')),
        );

        final controller = harness.controllers.single;
        final reader = tester.widget<CefrArticleReaderScreen>(
          find.byType(CefrArticleReaderScreen),
        );
        expect(reader.cefrLevel, level);
        expect(reader.sessionId, controller.state.sessionId);
        expect(reader.wordId, 'word:srs-gate-vocabulary');

        harness.features.emergencyOff(Feature.reading);
        await tester.pumpAndSettle();
        expect(controller.state.status, LessonSessionStatus.abandoned);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await harness.close();
      }
    },
  );

  for (final insideWindow in [false, true]) {
    testWidgets(
      'CEFR scans all candidate pages with eligible word inside first page=$insideWindow',
      (tester) async {
        final harness = await _SrsGateHarness.create();
        addTearDown(harness.close);
        var nextId = 0;
        final vocabulary = VocabularyUseCases(
          owners: harness.dependencies.localOwners!,
          vocabulary: DriftVocabularyRepository(harness.database),
          generateId: () =>
              'a-boundary-${(nextId++).toString().padLeft(3, '0')}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 15),
        );
        String? categoryId;
        String? eligibleInsideId;
        for (var i = 0; i < 100; i++) {
          if (i % 40 == 0) {
            categoryId = (await vocabulary.createCategory(
              'Boundary group $i',
            )).id;
          }
          final word = await vocabulary.createWord(
            CreateWordCommand(
              categoryId: categoryId!,
              spelling: 'candidate$i',
              meaning: 'synthetic candidate $i',
              partOfSpeech: 'noun',
              cefrLevel: insideWindow && i == 99 ? 'A2' : null,
            ),
          );
          if (insideWindow && i == 99) eligibleInsideId = word.id;
        }
        await harness.pump(tester);
        await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
        await _openConfiguredMode(
          tester,
          find.byKey(const ValueKey<String>('home/learn/reading/cefr')),
        );
        final reader = tester.widget<CefrArticleReaderScreen>(
          find.byType(CefrArticleReaderScreen),
        );
        expect(
          reader.wordId,
          insideWindow ? eligibleInsideId : 'word:srs-gate-vocabulary',
        );
        expect(reader.cefrLevel, insideWindow ? 'A2' : 'A1');
        harness.features.emergencyOff(Feature.reading);
        await tester.pumpAndSettle();
        expect(
          await harness.database.select(harness.database.answerAttempts).get(),
          hasLength(1),
          reason: 'opening or rejecting the route must not invent an answer',
        );
        final sessions = await harness.database
            .select(harness.database.learningSessions)
            .get();
        expect(sessions.where((session) => session.state == 'active'), isEmpty);
      },
    );
  }

  testWidgets(
    'Definition Quiz emergency-off terminally closes its durable shell session',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/definition')),
        itemCount: 1,
      );
      expect(find.byType(DefinitionQuizScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(DefinitionQuizScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'Cloze emergency-off closes its durable session and F24 at acceptance cutoff',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
        itemCount: 1,
      );
      expect(find.byType(FillInTheBlanksScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(FillInTheBlanksScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'Matching off fences a retained pair and closes durable session plus F24',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('matching-word-word:srs-gate-vocabulary'),
        ),
      );
      await tester.pump();
      final retained = tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey<String>(
                'matching-meaning-word:srs-gate-vocabulary',
              ),
            ),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      retained();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(MatchingModeScreen), findsNothing);
      expect(harness.repository.answerCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.abandoned,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final activeSessions = await (harness.database.select(
        harness.database.learningSessions,
      )..where((row) => row.state.equals('active'))).get();
      expect(activeSessions, isEmpty);
      final matchingAttempts = await (harness.database.select(
        harness.database.answerAttempts,
      )..where((row) => row.promptMode.equals('matchingPair'))).get();
      expect(matchingAttempts, isEmpty);
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'f16 Matching recovery ignores a newer mutable configuration preference',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      const adapter = MatchingModeAdapter();
      final owner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final configuration = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await harness.sessionConfigurations.save(
        configuration,
        updatedAtUtc: DateTime.utc(2026, 8, 25, 15),
      );
      final prepared = await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: configuration.itemCount,
        sessionConfiguration: configuration,
      );
      final close = learning.captureSessionClose(
        sessionId: prepared.session.id,
      );
      await prepared.persistClose(close: close, timeoutRequested: true);
      await close.finish();
      expect(harness.repository.finishCalls, 1);
      final newerPreference = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 3),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await harness.sessionConfigurations.save(
        newerPreference,
        updatedAtUtc: DateTime.utc(2026, 8, 25, 16),
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: null,
      );
      await tester.runAsync(() async {
        await harness.repository.matchingTerminalAcknowledged.future.timeout(
          const Duration(seconds: 1),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(harness.repository.finishCalls, 2);
      expect(harness.repository.abandonCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final timeSegments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(
        timeSegments.map(
          (segment) => segment.endedAtUtcMs >= segment.startedAtUtcMs,
        ),
        everyElement(isTrue),
      );
      final checkpoints =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      final latest = checkpoints
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .reduce(
            (left, right) =>
                (left['revision'] as int) > (right['revision'] as int)
                ? left
                : right,
          );
      expect(latest['terminalAcknowledged'], isTrue);
      expect(
        (latest['state'] as Map<String, dynamic>)['summaryPresented'],
        isTrue,
      );
      await tester.pump();
      expect(harness.repository.finishCalls, 2);
    },
  );

  testWidgets(
    'f16 Matching configuration drift requires an explicit discard decision',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      const adapter = MatchingModeAdapter();
      final owner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final pinned = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: pinned.itemCount,
        sessionConfiguration: pinned,
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 3,
      );

      expect(
        find.byKey(const ValueKey('session-configuration-recovery-prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-config-recovery-resume')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-config-recovery-discard')),
        findsOneWidget,
      );
      expect(harness.controllers, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('session-config-recovery-discard')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(harness.repository.abandonCalls, 1);
      expect(harness.controllers.single.sessionConfiguration?.itemCount, 3);
    },
  );

  testWidgets(
    'Matching recovery load and discard retain the owner captured before awaits',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        switchOwnerDuringProtocolResolution: true,
      );
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      final originalOwner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final pinned = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: originalOwner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      final prepared = await const MatchingModeAdapter().prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: pinned.itemCount,
        sessionConfiguration: pinned,
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 3,
      );

      expect(
        find.byKey(const ValueKey('session-configuration-recovery-prompt')),
        findsOneWidget,
        reason: 'the pre-await owner must still recover its active session',
      );
      await harness.database
          .into(harness.database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'matching-next-owner-active',
              ownerId: _OwnerSwitchingProtocolProvider.nextOwnerId,
              activityType: 'quiz',
              state: 'active',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                25,
                15,
                1,
              ).millisecondsSinceEpoch,
              appVersion: 'test',
              buildId: 'next-owner',
            ),
          );
      await tester.tap(
        find.byKey(const ValueKey('session-config-recovery-discard')),
      );
      await tester.pumpAndSettle();

      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(
        sessions.singleWhere((row) => row.id == prepared.session.id).state,
        'abandoned',
      );
      expect(
        sessions
            .singleWhere((row) => row.id == 'matching-next-owner-active')
            .state,
        'active',
      );
    },
  );

  testWidgets(
    'f16 Flashcard retirement waits for admitted evidence and terminal close',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        blockAnswer: true,
        blockAbandon: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.features.emergencyOff(Feature.srs);
      await tester.pump();
      harness.repository.answerRelease.complete();
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 1);
      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'f16 Matching retirement waits through checkpoint and evidence cleanup',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        blockMatchingCheckpoint: true,
        blockAbandon: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      const wordId = 'word:srs-gate-vocabulary';
      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('matching-word-$wordId')),
      );
      await tester.pumpAndSettle();
      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
      );
      await tester.runAsync(
        () => harness.repository.matchingCheckpointEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      await tester.pump();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.matchingCheckpointRelease.complete();
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 1);
      expect(harness.repository.abandonCalls, 1);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
      final checkpoints =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      final latest = checkpoints
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .reduce(
            (left, right) =>
                (left['revision'] as int) > (right['revision'] as int)
                ? left
                : right,
          );
      expect(
        (latest['state'] as Map<String, dynamic>)['pendingEvidence'],
        isNull,
      );
    },
  );

  testWidgets(
    'f16 Matching committed close lost ack survives emergency retirement and restart',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        loseMatchingCloseAckOnce: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      for (final wordId in const <String>[
        'word:srs-gate-vocabulary',
        'word:srs-gate-vocabulary-two',
      ]) {
        await _tapReachable(
          tester,
          find.byKey(ValueKey<String>('matching-word-$wordId')),
        );
        await tester.pumpAndSettle();
        await _tapReachable(
          tester,
          find.byKey(ValueKey<String>('matching-meaning-$wordId')),
        );
        await tester.pumpAndSettle();
      }
      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('matching-finish')),
      );
      await tester.runAsync(
        () => harness.repository.matchingCloseCommitted.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      final configured = sessions.singleWhere(
        (session) => session.activityType == MatchingModeAdapter.activityType,
      );
      expect(configured.state, 'completed');
      expect(harness.repository.abandonCalls, 0);
      expect(harness.repository.matchingCloseAppendCalls, 2);
      final recovered = await const MatchingModeAdapter().prepareSession(
        learning: harness.dependencies.learning!,
        evidence: harness.dependencies.currentActivityEvidence!,
        itemCount: 2,
        sessionConfiguration: harness.controllers.single.sessionConfiguration,
      );
      expect(recovered.session.id, configured.id);
      expect(recovered.completedSummary?.id, configured.id);
      final reconciled = await recovered.reconcileCompleted(
        completeSession: (close) =>
            close.requiresRetry ? close.retry() : close.finish(),
      );
      expect(reconciled.id, configured.id);
    },
  );

  testWidgets(
    'f16 Flashcard lost-ack retry and close survive finite effort expiry',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        loseAnswerAckOnce: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        timeLimitSeconds: 60,
      );
      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
        findsOneWidget,
      );

      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;
      await expectLater(
        harness.controllers.single.recordActiveLearningInteraction(
          DateTime.utc(2026, 8, 25, 15, 1),
        ),
        throwsA(isA<SessionConfigurationLimitReached>()),
      );
      await tester.pumpAndSettle();
      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      await tester.ensureVisible(retry);
      await _tapReachable(tester, retry);
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 2);
      expect(harness.repository.finishCalls, 1);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        harness.controllers.single.configurationActiveEffort,
        const Duration(seconds: 60),
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  testWidgets('f16 Matching lost-ack retry survives finite effort expiry', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      enableMatching: true,
      loseAnswerAckOnce: true,
      deterministicConfigurationClock: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
      itemCount: 2,
      timeLimitSeconds: 60,
    );
    const wordId = 'word:srs-gate-vocabulary';
    await _tapReachable(
      tester,
      find.byKey(const ValueKey<String>('matching-word-$wordId')),
    );
    await tester.pumpAndSettle();
    await _tapReachable(
      tester,
      find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
      findsOneWidget,
    );

    harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;
    await expectLater(
      harness.controllers.single.recordActiveLearningInteraction(
        DateTime.utc(2026, 8, 25, 15, 1),
      ),
      throwsA(isA<SessionConfigurationLimitReached>()),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey<String>('current-evidence-retry'));
    tester.widget<FilledButton>(retry).onPressed!();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 2);
    expect(
      harness.controllers.single.configurationActiveEffort,
      const Duration(seconds: 60),
    );
    expect(
      await harness.database.select(harness.database.answerAttempts).get(),
      hasLength(2),
    );
    expect(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
      findsNothing,
    );
  });

  testWidgets(
    'f16 untimed Matching idle time never schedules wall-clock completion',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
        untimed: true,
      );

      expect(
        find.text('กิจกรรมแบบไม่แสดงเวลานับถอยหลัง ยังมีขีดจำกัดเวลาเรียนจริง'),
        findsOneWidget,
      );
      await tester.pump(const Duration(hours: 1));
      await tester.pump();

      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(harness.repository.finishCalls, 0);
    },
  );

  testWidgets(
    'f16 Flashcard boundary tap cannot write after finite effort expires',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        timeLimitSeconds: 60,
      );
      harness.repository.blockConfigurationEffort();
      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;

      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.runAsync(
        () => harness.repository.configurationEffortEntered.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.releaseConfigurationEffort();
      await tester.pumpAndSettle();

      expect(harness.controllers.single.configurationLimitReached, isTrue);
      expect(harness.repository.answerCalls, 0);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'f16 Matching boundary tap cannot write after finite effort expires',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
        timeLimitSeconds: 60,
      );
      const wordId = 'word:srs-gate-vocabulary';
      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('matching-word-$wordId')),
      );
      await tester.pumpAndSettle();
      harness.repository.blockConfigurationEffort();
      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;

      await _tapReachable(
        tester,
        find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
      );
      await tester.runAsync(
        () => harness.repository.configurationEffortEntered.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.releaseConfigurationEffort();
      await tester.pumpAndSettle();

      expect(harness.controllers.single.configurationLimitReached, isTrue);
      expect(harness.repository.answerCalls, 0);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'SRS off synchronously fences a retained rating before terminal close',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockAbandon: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      expect(harness.activeTimes.single.state, ActiveLearningTimeState.active);
      final srsBefore =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();
      final staleRemembered = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('flashcard-remembered')),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.srs);
      staleRemembered();
      await tester.runAsync(
        () => harness.repository.abandonEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      final gatedSession = sessions.singleWhere(
        (session) => session.id == harness.controllers.single.state.sessionId,
      );
      expect(gatedSession.state, 'abandoned');
      expect(gatedSession.endedAtUtcMs, isNotNull);
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsBefore,
      );
    },
  );

  testWidgets(
    'SRS off awaits an accepted completion instead of racing abandonment',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockFinish: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await _scrollToModeEntry(tester, 'home/learn/srs');
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

      final remembered = find.byKey(
        const ValueKey<String>('flashcard-remembered'),
      );
      final staleNotRemembered = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('flashcard-not-remembered')),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
      await tester.tap(remembered);
      await tester.runAsync(
        () => harness.repository.finishEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final attemptsAtOff = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      final srsAtOff =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();

      harness.features.emergencyOff(Feature.srs);
      staleNotRemembered();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.finishRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions
            .singleWhere(
              (session) =>
                  session.id == harness.controllers.single.state.sessionId,
            )
            .state,
        'completed',
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(attemptsAtOff.length),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsAtOff,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'Quiz off during delayed initialization compensates the returned session',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayQuiz: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
        settleAfterStart: false,
      );
      await tester.runAsync(
        () => harness.repository.quizEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      harness.repository.quizRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(QuizScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Cloze off during delayed initialization compensates before screen attach',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayQuiz: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
        itemCount: 1,
        settleAfterStart: false,
      );
      await tester.runAsync(
        () => harness.repository.quizEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      harness.repository.quizRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(FillInTheBlanksScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets('Quiz off synchronously rejects a retained answer callback', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      enableQuizDistractor: true,
      blockAbandon: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
    );

    final answer = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
    final srsBefore =
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson();
    harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

    harness.features.emergencyOff(Feature.quiz);
    staleAnswer();
    await tester.runAsync(
      () => harness.repository.abandonEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );
    harness.repository.abandonRelease.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 0);
    expect(harness.repository.abandonCalls, 1);
    expect(
      await harness.database.select(harness.database.answerAttempts).get(),
      hasLength(1),
      reason: 'only the pre-existing SRS seed may remain',
    );
    expect(
      (await harness.database.select(harness.database.srsStates).get()).single
          .toJson(),
      srsBefore,
    );
    final sessions = await harness.database
        .select(harness.database.learningSessions)
        .get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segments, hasLength(1));
    expect(segments.single.activeDurationMs, 2000);
  });

  testWidgets(
    'typed route choice freezes hinted recognition until durable commit',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableQuizDistractor: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsBefore = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
        itemCount: 1,
        hintBudget: 2,
      );
      final controller = harness.controllers.single;
      final showStrategy = find.widgetWithText(FilledButton, 'ดูวิธีคิด');
      tester.widget<FilledButton>(showStrategy).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 1);

      final choice = find.byKey(
        const ValueKey<String>(
          'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
        ),
      );
      final submitChoice = tester.widget<FilledButton>(choice).onPressed!;
      harness.repository.armAnswerBlock();
      submitChoice();
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final revealContext = find.widgetWithText(FilledButton, 'ดูบริบทเพิ่ม');
      tester.widget<FilledButton>(revealContext).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 2);

      harness.repository.answerRelease.complete();
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final attempt = (await tester.runAsync(() async {
        return (await harness.database
                .select(harness.database.answerAttempts)
                .get())
            .singleWhere((row) => row.promptMode == 'meaningChoice');
      }))!;
      final context = EvidenceContext.fromJson(
        (jsonDecode(attempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      final command = harness.repository.commands.single;
      final commandEventContext = EvidenceContext.fromJson(
        (command.event!.payload['evidenceContext'] as Map)
            .cast<String, Object?>(),
      );
      expect(attempt.isCorrect, isTrue);
      expect(
        command.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(command.evidenceContext.hintLevel, 1);
      expect(commandEventContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(commandEventContext.hintLevel, 1);
      expect(context.evidenceClass, EvidenceClass.guidedPractice);
      expect(context.hintLevel, 1);
      final srsAfter = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;
      expect(srsAfter, srsBefore);
      expect(controller.hintState!.hintLevel, 0);
    },
  );

  testWidgets(
    'typed recall freezes support through pending mutation then resets it',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableTypedHintSequence: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsBefore = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
        itemCount: 3,
        hintBudget: 2,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
          ),
        ),
      );
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      final input = find.byKey(const ValueKey<String>('typed-recall-input'));
      for (var pump = 0; pump < 50 && input.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(find.text('able to recover'), findsOneWidget);
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ดูวิธีคิด'))
          .onPressed!();
      await tester.pump();
      expect(
        find.text(
          'Recall the spelling pattern before entering the whole word.',
        ),
        findsOneWidget,
      );
      final controller = harness.controllers.single;
      expect(controller.hintState!.hintLevel, 1);

      harness.repository.armAnswerBlock();
      await tester.enterText(input, 'resilient');
      final submit = find.byKey(const ValueKey<String>('typed-recall-submit'));
      await tester.pump();
      tester.widget<FilledButton>(submit).onPressed!();
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      expect(
        controller.hintState!.hintLevel,
        1,
        reason: 'per-item support must remain frozen while evidence is pending',
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ดูบริบทเพิ่ม'),
          )
          .onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 2);

      harness.repository.answerRelease.complete();
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final typedAttempt = (await tester.runAsync(() async {
        return (await harness.database
                .select(harness.database.answerAttempts)
                .get())
            .singleWhere((attempt) => attempt.promptMode == 'typedRecall');
      }))!;
      final typedContext = EvidenceContext.fromJson(
        (jsonDecode(typedAttempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      final typedCommand = harness.repository.commands.singleWhere(
        (command) => command.promptMode == 'typedRecall',
      );
      final typedEventContext = EvidenceContext.fromJson(
        (typedCommand.event!.payload['evidenceContext'] as Map)
            .cast<String, Object?>(),
      );
      expect(typedAttempt.isCorrect, isTrue);
      expect(
        typedCommand.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(typedCommand.evidenceContext.hintLevel, 1);
      expect(typedEventContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(typedEventContext.hintLevel, 1);
      expect(typedContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(typedContext.hintLevel, 1);
      final srsAfter = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;
      expect(srsAfter, srsBefore);
      expect(controller.hintState!.hintLevel, 0);
      expect(find.text('ดูวิธีคิด'), findsOneWidget);

      tester.widget<FilledButton>(next).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 0);
      expect(find.text('ดูวิธีคิด'), findsOneWidget);
    },
  );

  testWidgets('Quiz off synchronously rejects a retained typed callback', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      blockAbandon: true,
      enableMatching: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
      itemCount: 2,
      hintBudget: 2,
    );

    final choice = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    tester.widget<FilledButton>(choice).onPressed!();
    final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
    for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    tester.widget<FilledButton>(next).onPressed!();
    final input = find.byKey(const ValueKey<String>('typed-recall-input'));
    for (var pump = 0; pump < 50 && input.evaluate().isEmpty; pump++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.tap(find.text('ดูวิธีคิด'));
    await tester.pump();
    await tester.tap(find.text('ดูบริบทเพิ่ม'));
    await tester.pump();
    expect(harness.controllers.single.hintState!.hintLevel, 2);
    await tester.enterText(input, 'stable');
    await tester.pump();
    final submit = find.byKey(const ValueKey<String>('typed-recall-submit'));
    final staleSubmit = tester.widget<FilledButton>(submit).onPressed!;

    harness.features.emergencyOff(Feature.quiz);
    staleSubmit();
    await tester.runAsync(
      () => harness.repository.abandonEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );
    harness.repository.abandonRelease.complete();
    await tester.pumpAndSettle();

    expect(
      harness.repository.answerCalls,
      1,
      reason: 'only the accepted first recognition may reach persistence',
    );
    final attempts = await harness.database
        .select(harness.database.answerAttempts)
        .get();
    expect(
      attempts.where((attempt) => attempt.promptMode == 'typedRecall'),
      isEmpty,
    );
  });

  testWidgets('Quiz off freezes time while accepted evidence settles', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      enableQuizDistractor: true,
      blockAnswer: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
    );

    final answer = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
    final srsBefore =
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson();
    harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
    staleAnswer();
    await tester.runAsync(
      () => harness.repository.answerEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );

    harness.features.emergencyOff(Feature.quiz);
    staleAnswer();
    await tester.pump();
    expect(
      harness.repository.abandonCalls,
      0,
      reason: 'terminalization must wait the accepted evidence operation',
    );
    harness.monotonicMicros = const Duration(hours: 1).inMicroseconds;
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();
    expect(
      harness.activeTimes.single.state,
      ActiveLearningTimeState.finished,
      reason: 'F24 must close while the accepted evidence write is blocked',
    );
    final segmentsWhileBlocked = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segmentsWhileBlocked, hasLength(1));
    expect(segmentsWhileBlocked.single.activeDurationMs, 2000);
    harness.repository.answerRelease.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 1);
    expect(harness.repository.abandonCalls, 1);
    final attempts = await harness.database
        .select(harness.database.answerAttempts)
        .get();
    expect(attempts, hasLength(2));
    final recognition = attempts.singleWhere(
      (attempt) => attempt.promptMode == 'meaningChoice',
    );
    expect(recognition.evidenceClass, EvidenceClass.recognition.name);
    expect(
      (await harness.database.select(harness.database.srsStates).get()).single
          .toJson(),
      srsBefore,
    );
    final sessions = await harness.database
        .select(harness.database.learningSessions)
        .get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segments, hasLength(1));
    expect(segments.single.activeDurationMs, 2000);
  });

  testWidgets(
    'Quiz off awaits an accepted final completion without abandonment race',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableQuizDistractor: true,
        blockFinish: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
      );

      final answer = find.byKey(
        const ValueKey<String>(
          'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
        ),
      );
      final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
      await tester.tap(answer);
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.runAsync(
        () => harness.repository.finishEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final attemptsAtOff = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      final srsAtOff =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();

      harness.features.emergencyOff(Feature.quiz);
      staleAnswer();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.finishRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'completed'),
        hasLength(2),
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(attemptsAtOff.length),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsAtOff,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );
}

const _testPackIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:f16-pinned',
  revision: 3,
);

LearningPackDetail _testPinnedPack({
  List<String> vocabularyWordIds = const <String>['word:srs-gate-vocabulary'],
}) => LearningPackDetail(
  summary: LearningPackSummary(
    packId: _testPackIdentity.id,
    revision: _testPackIdentity.revision,
    title: 'Pinned f16 pack',
    cefrLevel: 'A1',
    topic: 'durability',
    skill: 'recognition',
    goal: 'practice',
    contentIdentity: _testPackIdentity,
  ),
  vocabularyWordIds: vocabularyWordIds,
);

final class _StaleSessionConfigurationProtocolProvider
    implements SessionConfigurationProtocolProvider {
  const _StaleSessionConfigurationProtocolProvider();

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(String ownerId) =>
      Future<SessionConfigurationProtocolLimits>.error(
        const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.staleProtocol,
        ),
      );
}

final class _OwnerSwitchingProtocolProvider
    implements SessionConfigurationProtocolProvider {
  _OwnerSwitchingProtocolProvider({
    required this.delegate,
    required this.database,
  });

  static const nextOwnerId = 'matching-recovery-next-owner';

  final SessionConfigurationProtocolProvider delegate;
  final AppDatabase database;
  bool _switched = false;

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async {
    final limits = await delegate.resolveForOwner(ownerId);
    if (_switched) return limits;
    _switched = true;
    await database.transaction(() async {
      await database.customStatement(
        'UPDATE local_owners SET is_active = 0 WHERE id = ?',
        <Object?>[ownerId],
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: nextOwnerId,
              createdAtUtcMs: DateTime.utc(
                2026,
                8,
                25,
                15,
                1,
              ).millisecondsSinceEpoch,
            ),
          );
    });
    return limits;
  }
}

final class _PinnedPackRepository implements LearningPackRepository {
  const _PinnedPackRepository(this.detail);

  final LearningPackDetail detail;

  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async {
    if (packId != detail.summary.packId ||
        revision != detail.summary.revision) {
      throw StateError('Pinned pack version unavailable.');
    }
    return detail;
  }

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      filter.matches(detail.summary)
      ? <LearningPackSummary>[detail.summary]
      : const <LearningPackSummary>[];
}

final class _SrsGateHarness {
  _SrsGateHarness._({
    required this.database,
    required this.features,
    required this.repository,
    required this.dependencies,
    required this.controllers,
    required this.activeTimes,
    required this.sessionConfigurations,
  });

  final AppDatabase database;
  final RuntimeFeatureRegistry features;
  final _CoordinatedLearningRepository repository;
  final AppDependencies dependencies;
  final List<UnifiedLessonController> controllers;
  final List<ActiveLearningTimeController> activeTimes;
  final DriftSessionConfigurationStore sessionConfigurations;
  int monotonicMicros = 0;

  static Future<_SrsGateHarness> create({
    bool delayDue = false,
    bool delayQuiz = false,
    bool blockAbandon = false,
    bool blockAnswer = false,
    bool blockFinish = false,
    bool loseAnswerAckOnce = false,
    bool loseMatchingCloseAckOnce = false,
    bool blockMatchingCheckpoint = false,
    bool enableMatching = false,
    bool enableHandwriting = false,
    bool enableTypedHintSequence = false,
    bool enableQuizDistractor = false,
    bool deterministicConfigurationClock = false,
    String? vocabularyCefrLevel = 'A1',
    LearningPackDetail? pinnedPack,
    bool staleProtocol = false,
    bool switchOwnerDuringProtocolResolution = false,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 8, 25, 15);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'srs-gate-owner',
      nowUtc: () => now,
    );
    var vocabularyId = 0;
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => switch (vocabularyId++) {
        0 || 1 => 'srs-gate-vocabulary',
        2 => 'srs-gate-vocabulary-two',
        _ => 'srs-gate-vocabulary-three',
      },
      nowUtc: () => now,
    );
    final category = await vocabulary.createCategory('SRS gate');
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'durable',
        meaning: 'lasting',
        partOfSpeech: 'adjective',
        cefrLevel: vocabularyCefrLevel,
      ),
    );
    final driftLearning = DriftLearningRepository(database);
    var seedId = 0;
    final seedTime = now.subtract(const Duration(days: 2));
    final seedLearning = LearningUseCases(
      owners: owners,
      repository: driftLearning,
      generateId: () => 'srs-gate-seed-${++seedId}',
      nowUtc: () => seedTime,
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'f06-live-srs-gate-seed',
      ),
    );
    final seedSession = await seedLearning.startQuiz();
    await seedLearning.recordEvidence(
      sourceEvidenceId: 'attempt:srs-gate-seed',
      occurredAtUtc: seedTime,
      sessionId: seedSession.id,
      wordId: seedSession.questions.single.word.id,
      promptMode: 'srsRecall',
      isCorrect: true,
      responseTimeMs: 100,
      attemptNumber: 1,
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'srs-recall',
        hintLevel: 0,
        contentRevision: 'built-in-v1',
        engagementAllowed: true,
      ),
    );
    await seedLearning.finishSession(seedSession.id);
    if (enableMatching || enableTypedHintSequence) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'stable',
          meaning: 'not likely to change',
          partOfSpeech: 'adjective',
        ),
      );
    }
    if (enableTypedHintSequence) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'resilient',
          meaning: 'able to recover',
          partOfSpeech: 'adjective',
        ),
      );
    }
    if (enableQuizDistractor) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'alternative',
          meaning: 'another choice',
          partOfSpeech: 'noun',
        ),
      );
    }
    final repository = _CoordinatedLearningRepository(
      driftLearning,
      delayDue: delayDue,
      delayQuiz: delayQuiz,
      blockAbandon: blockAbandon,
      blockAnswer: blockAnswer,
      blockFinish: blockFinish,
      loseAnswerAckOnce: loseAnswerAckOnce,
      loseMatchingCloseAckOnce: loseMatchingCloseAckOnce,
      blockMatchingCheckpoint: blockMatchingCheckpoint,
    );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'srs-gate-${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'f06-live-srs-gate',
      ),
    );
    final learningTime = DriftLearningTimeRepository(database, owners: owners);
    final controllers = <UnifiedLessonController>[];
    final activeTimes = <ActiveLearningTimeController>[];
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    final modes = buildLessonModeRegistry(
      handwritingDeliveryState: enableHandwriting
          ? LessonModeDeliveryState.enabled
          : LessonModeDeliveryState.implementedOff,
      matchingDeliveryState: enableMatching
          ? LessonModeDeliveryState.enabled
          : LessonModeDeliveryState.implementedOff,
    );
    final research = InertResearchDependencies(database);
    final sessionConfigurations = DriftSessionConfigurationStore(database);
    final persistedSessionConfigurationProtocols =
        PersistedSessionConfigurationProtocolProvider(
          currentResearchState: research.assignedLearningEventContext,
          rolloutMode: research.evidencePolicyRolloutModeProvider,
          nowUtc: () => now,
          catalog: SessionConfigurationProtocolCatalog(
            baseline: const SessionConfigurationProtocolLimits.standard(),
          ),
        );
    final SessionConfigurationProtocolProvider sessionConfigurationProtocols =
        staleProtocol
        ? const _StaleSessionConfigurationProtocolProvider()
        : switchOwnerDuringProtocolResolution
        ? _OwnerSwitchingProtocolProvider(
            delegate: persistedSessionConfigurationProtocols,
            database: database,
          )
        : persistedSessionConfigurationProtocols;
    final studyPlanning = pinnedPack == null
        ? null
        : StudyPlanningUseCases(
            packs: _PinnedPackRepository(pinnedPack),
            progress: ProgressUseCases(
              owners: owners,
              queries: DriftProgressQueries(database),
              nowUtc: () => now,
            ),
          );
    late final _SrsGateHarness harness;
    final dependencies = AppDependencies(
      initialRoute: AppRoute.home,
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      quest: testQuestUseCases(),
      experiments: research.experiments,
      consents: research.consents,
      experimentAssignments: research.experimentAssignments,
      assignedLearningEventContext: research.assignedLearningEventContext,
      evidencePolicyRolloutModeProvider:
          research.evidencePolicyRolloutModeProvider,
      features: features,
      database: database,
      localOwners: owners,
      learning: learning,
      vocabulary: vocabulary,
      lessonModes: modes,
      sessionConfigurationProtocols: sessionConfigurationProtocols,
      sessionConfigurations: sessionConfigurations,
      currentActivityEvidence: CurrentActivityEvidenceAdapter(
        learning: learning,
      ),
      associativeLearning: InMemoryAssociativeLearningAdapter(),
      studyPlanning: studyPlanning,
      learningTime: learningTime,
      learningTimeCaptureRollout: const LearningTimeCaptureRollout.internal(),
      createLessonController: (adapter) {
        final activeTime = ActiveLearningTimeController(
          repository: learningTime,
          monotonicMicros: () => harness.monotonicMicros,
          nowUtc: () => now,
          timezoneContext: (_) => const LearningTimeZoneContext(
            timezoneId: 'Etc/UTC',
            utcOffsetMinutes: 0,
          ),
        );
        activeTimes.add(activeTime);
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: adapter,
          activeLearningTime: activeTime,
          configurationMonotonicMicros: deterministicConfigurationClock
              ? () => harness.monotonicMicros
              : null,
        );
        controllers.add(controller);
        return controller;
      },
    );
    harness = _SrsGateHarness._(
      database: database,
      features: features,
      repository: repository,
      dependencies: dependencies,
      controllers: controllers,
      activeTimes: activeTimes,
      sessionConfigurations: sessionConfigurations,
    );
    return harness;
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: const MaterialApp(home: ChooseModeScreen()),
    ),
  );

  Future<void> close() async {
    repository.releaseAll();
    features.dispose();
    await database.close();
  }
}

final class _CoordinatedLearningRepository
    implements
        LearningRepository,
        PagedQuizWordRepository,
        LearningSessionLifecycleRepository,
        SessionConfiguredLearningRepository,
        LearningActivityRecoveryRepository,
        PinnedLearningContentRepository {
  _CoordinatedLearningRepository(
    this.delegate, {
    required this.delayDue,
    required this.delayQuiz,
    required this.blockAbandon,
    required this.blockAnswer,
    required this.blockFinish,
    required this._loseAnswerAckOnce,
    required this._loseMatchingCloseAckOnce,
    required this._blockMatchingCheckpoint,
  });

  final LearningRepository delegate;
  final bool delayDue;
  final bool delayQuiz;
  final bool blockAbandon;
  bool blockAnswer;
  final bool blockFinish;
  bool _loseAnswerAckOnce;
  bool _loseMatchingCloseAckOnce;
  bool _blockMatchingCheckpoint;
  final Completer<void> dueEntered = Completer<void>();
  final Completer<void> dueRelease = Completer<void>();
  final Completer<void> quizEntered = Completer<void>();
  final Completer<void> quizRelease = Completer<void>();
  final Completer<void> answerEntered = Completer<void>();
  final Completer<void> answerRelease = Completer<void>();
  final Completer<void> abandonEntered = Completer<void>();
  final Completer<void> abandonRelease = Completer<void>();
  final Completer<void> finishEntered = Completer<void>();
  final Completer<void> finishRelease = Completer<void>();
  final Completer<void> matchingTerminalAcknowledged = Completer<void>();
  final Completer<void> matchingCheckpointEntered = Completer<void>();
  final Completer<void> matchingCheckpointRelease = Completer<void>();
  final Completer<void> matchingCloseCommitted = Completer<void>();
  Completer<void>? _configurationEffortEntered;
  Completer<void>? _configurationEffortRelease;
  int abandonCalls = 0;
  int answerCalls = 0;
  int finishCalls = 0;
  int matchingCloseAppendCalls = 0;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];

  void armAnswerBlock() => blockAnswer = true;

  @override
  Future<List<QuizWord>> listQuizWordPage({
    required String ownerId,
    String? categoryId,
    String? afterId,
    required int limit,
  }) async {
    if (delayQuiz) {
      if (!quizEntered.isCompleted) quizEntered.complete();
      await quizRelease.future;
    }
    return (delegate as PagedQuizWordRepository).listQuizWordPage(
      ownerId: ownerId,
      categoryId: categoryId,
      afterId: afterId,
      limit: limit,
    );
  }

  Future<void> get configurationEffortEntered =>
      _configurationEffortEntered!.future;

  void blockConfigurationEffort() {
    _configurationEffortEntered = Completer<void>();
    _configurationEffortRelease = Completer<void>();
  }

  void releaseConfigurationEffort() {
    final release = _configurationEffortRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async {
    if (delayQuiz) {
      if (!quizEntered.isCompleted) quizEntered.complete();
      await quizRelease.future;
    }
    return delegate.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      limit: limit,
    );
  }

  @override
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  }) => (delegate as PinnedLearningContentRepository).listPinnedQuizWords(
    ownerId: ownerId,
    wordIds: wordIds,
  );

  @override
  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  }) => (delegate as PinnedLearningContentRepository).listExactPinnedQuizWords(
    ownerId: ownerId,
    content: content,
  );

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    if (delayDue) {
      if (!dueEntered.isCompleted) dueEntered.complete();
      await dueRelease.future;
    }
    return delegate.listDueWords(
      ownerId: ownerId,
      nowUtc: nowUtc,
      limit: limit,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) => (delegate as SessionConfiguredLearningRepository)
      .loadSessionConfigurationState(ownerId: ownerId, sessionId: sessionId);

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) async {
    final entered = _configurationEffortEntered;
    final release = _configurationEffortRelease;
    if (entered != null && release != null) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      _configurationEffortEntered = null;
      _configurationEffortRelease = null;
    }
    return (delegate as SessionConfiguredLearningRepository)
        .addSessionConfigurationActiveEffort(
          ownerId: ownerId,
          sessionId: sessionId,
          configurationIdentity: configurationIdentity,
          delta: delta,
        );
  }

  @override
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  }) => (delegate as LearningActivityRecoveryRepository)
      .startSessionWithCheckpoint(session: session, checkpoint: checkpoint);

  @override
  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  }) => (delegate as LearningActivityRecoveryRepository)
      .loadLatestActivityRecovery(ownerId: ownerId, activityType: activityType);

  @override
  Future<LearningActivityRecovery?> loadExactActivityRecovery({
    required String ownerId,
    required String sessionId,
    required String activityType,
  }) => (delegate as LearningActivityRecoveryRepository)
      .loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: sessionId,
        activityType: activityType,
      );

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    if (checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingCloseAtUtc'] != null &&
        !checkpoint.terminalAcknowledged) {
      matchingCloseAppendCalls += 1;
    }
    if (_blockMatchingCheckpoint &&
        checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingEvidence'] != null) {
      _blockMatchingCheckpoint = false;
      if (!matchingCheckpointEntered.isCompleted) {
        matchingCheckpointEntered.complete();
      }
      await matchingCheckpointRelease.future;
    }
    await (delegate as LearningActivityRecoveryRepository)
        .appendActivityCheckpoint(ownerId: ownerId, checkpoint: checkpoint);
    if (_loseMatchingCloseAckOnce &&
        checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingCloseAtUtc'] != null &&
        !checkpoint.terminalAcknowledged) {
      _loseMatchingCloseAckOnce = false;
      if (!matchingCloseCommitted.isCompleted) {
        matchingCloseCommitted.complete();
      }
      throw StateError('simulated committed close checkpoint ack loss');
    }
    if (checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.terminalAcknowledged &&
        !matchingTerminalAcknowledged.isCompleted) {
      matchingTerminalAcknowledged.complete();
    }
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    abandonCalls += 1;
    if (blockAbandon) {
      if (!abandonEntered.isCompleted) abandonEntered.complete();
      await abandonRelease.future;
    }
    return (delegate as LearningSessionLifecycleRepository).abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls += 1;
    if (blockFinish) {
      if (!finishEntered.isCompleted) finishEntered.complete();
      await finishRelease.future;
    }
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answerCalls += 1;
    commands.add(command);
    if (blockAnswer) {
      if (!answerEntered.isCompleted) answerEntered.complete();
      await answerRelease.future;
    }
    final result = await delegate.recordAnswer(command);
    if (_loseAnswerAckOnce) {
      _loseAnswerAckOnce = false;
      throw StateError('simulated committed answer acknowledgement loss');
    }
    return result;
  }

  void releaseAll() {
    releaseConfigurationEffort();
    if (!dueRelease.isCompleted) dueRelease.complete();
    if (!quizRelease.isCompleted) quizRelease.complete();
    if (!answerRelease.isCompleted) answerRelease.complete();
    if (!abandonRelease.isCompleted) abandonRelease.complete();
    if (!finishRelease.isCompleted) finishRelease.complete();
    if (!matchingCheckpointRelease.isCompleted) {
      matchingCheckpointRelease.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _InertSpeechGateway implements SpeechRecognitionGateway {
  @override
  bool get isListening => false;

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.unavailable;

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
