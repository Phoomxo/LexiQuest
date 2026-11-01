import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/review_center_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Reading time wraps at 320px/200 percent with IME $brightness',
      (tester) async {
        final h = await _TimeHarness.open(tester);
        addTearDown(() => tester.runAsync(h.close));
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final words = await tester.runAsync(
          () => h.base.learningRepository.listQuizWords(
            ownerId: configuredOwnerId,
            limit: 1,
          ),
        );
        final word = words!.single;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 240),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'A1',
              targetWords: [word.spelling],
              passageText: 'Synthetic narrow reading.',
              targetWordIds: {word.spelling: word.id},
              targetWordContentRevisions: {
                word.spelling: word.contentRevision!,
              },
              ownerId: configuredOwnerId,
              learning: h.base.learning,
              learningTime: h.time,
            ),
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final context in [
    LearningTimeCallerContext.ordinary,
    LearningTimeCallerContext.researchControlled,
  ]) {
    testWidgets(
      'early reading records only confirmed ordinary input $context',
      (tester) async {
        final h = await _TimeHarness.open(tester);
        addTearDown(() => tester.runAsync(h.close));
        final words = await tester.runAsync(
          () => h.base.learningRepository.listQuizWords(
            ownerId: configuredOwnerId,
            limit: 1,
          ),
        );
        final word = words!.single;
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'A1',
              targetWords: [word.spelling],
              passageText: 'Synthetic immutable reading passage.',
              targetWordIds: {word.spelling: word.id},
              targetWordContentRevisions: {
                word.spelling: word.contentRevision!,
              },
              ownerId: configuredOwnerId,
              learning: h.base.learning,
              learningTime: h.time,
              timeCallerContext: context,
            ),
          ),
        );
        await _settle(tester);
        expect(
          await tester.runAsync(() => h.rows('learning_time_scopes')),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => h.rows('learning_sessions')),
          isEmpty,
        );
        h.micros += 2000000;
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await _settle(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.time.retryPending);
        final value = await tester.runAsync(
          () => h.time.read(const OwnerTimeRead()),
        );
        expect(
          value!.activeDurationUs,
          context == LearningTimeCallerContext.ordinary ? 2000000 : 0,
        );
        expect(
          await tester.runAsync(() => h.rows('learning_sessions')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Tutor excludes provider wait and playback until stop ACK', (
    tester,
  ) async {
    final h = await _TimeHarness.open(tester);
    addTearDown(() => tester.runAsync(h.close));
    final tutor = _Tutor();
    final voice = _Voice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          geminiTutor: tutor,
          voice: VoiceUseCases(voice),
          learningTime: h.time,
        ),
      ),
    );
    await _settle(tester);
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    h.micros += 2000000;
    await tester.enterText(input, 'Synthetic private draft');
    await _settle(tester);
    h.micros += 3000000;
    await tester.enterText(input, 'Synthetic private revised draft');
    await _settle(tester);
    h.micros += 1000000;
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();
    h.micros += 40000000;
    tutor.replyGate.complete();
    await _settle(tester);
    expect(voice.speaks, 1);
    h.micros += 20000000;
    await tester.enterText(input, 'User resumes after playback');
    await _settle(tester);
    expect(voice.stops, greaterThan(0));
    h.micros += 3000000;
    await tester.enterText(input, 'Next actual edit');
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.time.retryPending);
    final value = await tester.runAsync(
      () => h.time.read(const OwnerTimeRead()),
    );
    expect(value!.activeDurationUs, 9000000);
    expect(await tester.runAsync(() => h.rows('learning_sessions')), isEmpty);
    final rows = await tester.runAsync(() => h.rows('learning_time_segments'));
    expect(rows.toString(), isNot(contains('private')));
    expect(rows.toString(), isNot(contains('User resumes')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('default-off Tutor never creates a time fact', (tester) async {
    final h = await _TimeHarness.open(tester, enabled: false);
    addTearDown(() => tester.runAsync(h.close));
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          geminiTutor: _Tutor(),
          voice: VoiceUseCases(_Voice()),
          learningTime: h.time,
        ),
      ),
    );
    await _settle(tester);
    h.micros += 4000000;
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Actual edit',
    );
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.time.retryPending);
    expect(
      await tester.runAsync(() => h.rows('learning_time_scopes')),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => h.rows('learning_time_segments')),
      isEmpty,
    );
  });

  testWidgets('Tutor context replacement retires ordinary input permission', (
    tester,
  ) async {
    final h = await _TimeHarness.open(tester);
    addTearDown(() => tester.runAsync(h.close));
    final tutor = _Tutor();
    final voice = VoiceUseCases(_Voice());
    Widget app(LearningTimeCallerContext caller) => MaterialApp(
      home: AiTutorScreen(
        geminiTutor: tutor,
        voice: voice,
        learningTime: h.time,
        timeCallerContext: caller,
      ),
    );
    await tester.pumpWidget(app(LearningTimeCallerContext.ordinary));
    await _settle(tester);
    expect(h.time.liveLease, isNotNull);
    h.micros += 2000000;
    await tester.pumpWidget(app(LearningTimeCallerContext.researchControlled));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Controlled edit',
    );
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.time.retryPending);
    expect(
      await tester.runAsync(() => h.rows('learning_time_segments')),
      isEmpty,
    );
  });

  testWidgets('old lifecycle stop cannot admit newer Tutor playback', (
    tester,
  ) async {
    final h = await _TimeHarness.open(tester);
    addTearDown(() => tester.runAsync(h.close));
    final tutor = _Tutor()..replyGate.complete();
    final voice = _Voice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          geminiTutor: tutor,
          voice: VoiceUseCases(voice),
          learningTime: h.time,
        ),
      ),
    );
    await _settle(tester);
    final oldStop = Completer<void>();
    voice.stopGate = oldStop;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    await tester.enterText(input, 'New response after resuming');
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await _settle(tester);
    expect(voice.speaks, 1);
    oldStop.complete();
    await _settle(tester);
    final stopsBeforeEdit = voice.stops;
    h.micros += 5000000;
    await tester.enterText(input, 'Actual edit must stop newer playback');
    await _settle(tester);
    expect(voice.stops, stopsBeforeEdit + 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retired optional time does not block canonical Reading recall', (
    tester,
  ) async {
    final h = await _TimeHarness.open(tester);
    addTearDown(() => tester.runAsync(h.close));
    final words = await tester.runAsync(
      () => h.base.learningRepository.listQuizWords(
        ownerId: configuredOwnerId,
        limit: 1,
      ),
    );
    final word = words!.single;
    await tester.pumpWidget(
      MaterialApp(
        home: AssociativeReadingSessionScreen(
          cefrLevel: 'A1',
          targetWords: [word.spelling],
          passageText: 'Synthetic isolated reading.',
          targetWordIds: {word.spelling: word.id},
          targetWordContentRevisions: {word.spelling: word.contentRevision!},
          ownerId: configuredOwnerId,
          learning: h.base.learning,
          learningTime: h.time,
        ),
      ),
    );
    await _settle(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _settle(tester);
    }
    h.time.retireDependencies();
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, word.spelling);
    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _settle(tester);
    expect(find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'), findsOneWidget);
    expect(
      await tester.runAsync(() => h.rows('answer_attempts')),
      hasLength(1),
    );
    expect(
      await tester.runAsync(() => h.rows('learning_sessions')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

final class _TimeHarness {
  _TimeHarness(this.base) {
    time = LearningTimeUseCases(
      repository: DriftLearningTimeRepository(
        database: base.database,
        ownerWrites: base.ownerWrites,
        learning: base.learningRepository,
      ),
      ownerChanges: base.ownerChanges,
      monotonicMicros: () => micros,
      nowUtc: () => base.now,
      generateId: () => 'synthetic-reading-tutor-${id++}',
    );
  }
  final ReviewCenterHarness base;
  late final LearningTimeUseCases time;
  int micros = 0;
  int id = 0;
  static Future<_TimeHarness> open(
    WidgetTester tester, {
    bool enabled = true,
  }) async => (await tester.runAsync(() async {
    final h = _TimeHarness(await ReviewCenterHarness.open());
    if (h.time.preference == null) {
      await h.time.changes
          .firstWhere((_) => h.time.preference != null)
          .timeout(const Duration(seconds: 5));
    }
    if (enabled) {
      final result = await h.time.setEnabled(
        true,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(result?.enabled, isTrue);
    }
    return h;
  }))!;
  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await base.database.customSelect('SELECT * FROM $table').get())
      row.data,
  ];
  Future<void> close() async {
    await time.dispose();
    await base.close();
  }
}

final class _Tutor implements GeminiTutorController {
  @override
  GeminiScope? get scope => const GeminiScope(
    ownerId: configuredOwnerId,
    firebaseUid: null,
    isAnonymous: true,
  );
  @override
  int get epoch => 0;
  @override
  Stream<int> get invalidations => const Stream.empty();
  final replyGate = Completer<void>();
  @override
  Future<GeminiSettingsStatus> loadSettings() async =>
      const GeminiSettingsStatus(
        hasKey: true,
        providerConsent: true,
        shareLearningSummary: false,
      );
  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  }) async {
    await replyGate.future;
    return GeminiTutorReply(
      text: 'Synthetic reply',
      model: 'synthetic-model',
      generatedAtUtc: DateTime.utc(2026, 11, 1),
    );
  }

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) async {}
  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {}
  @override
  Future<void> removeKey() async {}
  @override
  Future<void> dispose() async {}
}

final class _Voice implements VoiceProvider {
  int speaks = 0;
  int stops = 0;
  Completer<void>? stopGate;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    speaks++;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    final gate = stopGate;
    stopGate = null;
    await gate?.future;
  }
}
