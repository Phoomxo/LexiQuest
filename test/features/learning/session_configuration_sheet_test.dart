import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  const policy = SessionConfigurationPolicy();
  const pack = ContentIdentity(
    type: ContentType.learningPack,
    id: 'pack:starter',
    revision: 2,
  );
  const limits = SessionConfigurationProtocolLimits(
    schemaVersion: 1,
    protocolId: 'protocol:sheet-test',
    protocolVersion: '1',
    minimumItemCount: 2,
    maximumItemCount: 12,
    maximumHintBudget: 2,
    minimumTimedSeconds: 60,
    maximumTimedSeconds: 1200,
    allowsUntimedAlternative: true,
    maximumUntimedActiveEffortSeconds: 900,
    pinnedPackIdentities: <ContentIdentity>[pack],
  );
  final registration = LessonModeRegistration(
    adapter: const MeaningQuizModeAdapter(),
    feature: Feature.quiz,
    productionEntryId: 'home/learn/quiz',
    routeName: 'learning/quiz',
  );

  for (final fieldKey in ['session-item-count', 'session-time-limit-seconds']) {
    for (final pending in [true, false]) {
      testWidgets('B06 config $fieldKey rejects ${pending ? 'composing' : 'blank'} then accepts completed input', (tester) async {
        SessionConfiguration? result;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: FilledButton(onPressed: () async {
            result = await showSessionConfigurationSheet(
              context: context, registration: registration, policy: policy,
              limits: limits, ownerId: 'owner:ime', packs: const [SessionConfigurationPackOption(identity: pack, label: 'ชุดฝึกจริง')],
            );
          }, child: const Text('open')),
        ))));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ปรับตัวเลือก'));
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey(fieldKey));
        await tester.ensureVisible(field);
        final controller = tester.widget<TextField>(field).controller!;
        final text = fieldKey == 'session-item-count' ? '6' : '600';
        controller.value = TextEditingValue(text: pending ? text : '', composing: pending ? TextRange(start: 0, end: text.length) : TextRange.empty);
        final submit = tester.widget<FilledButton>(find.byKey(const ValueKey('session-config-start'))).onPressed!;
        submit();
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(SessionConfigurationSheet), findsOneWidget);
        controller.value = TextEditingValue(text: text);
        submit();
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(find.byType(SessionConfigurationSheet), findsNothing);
      });
    }
  }

  for (final adapter in <LessonModeAdapter>[
    const DictationModeAdapter(),
    const MatchingModeAdapter(),
  ]) {
    testWidgets(
      'compact cap and source follow ${adapter.mode.name} capability',
      (tester) async {
        final mode = LessonModeRegistration(
          adapter: adapter,
          feature: Feature.quiz,
          productionEntryId: 'home/learn/quiz',
          routeName: 'learning/${adapter.mode.name}',
        );
        final scopedLimits = const SessionConfigurationProtocolLimits.standard()
            .copyWith(minimumTimedSeconds: 90, maximumTimedSeconds: 90);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SessionConfigurationSheet(
                registration: mode,
                policy: policy,
                limits: scopedLimits,
                ownerId: 'owner:capabilities',
                packs: const [],
              ),
            ),
          ),
        );
        final expected = policy.defaultsFor(
          registration: mode,
          limits: scopedLimits,
        );
        expect(
          find.textContaining('จำนวน ${expected.itemCount} ข้อ'),
          findsOneWidget,
        );
        expect(find.textContaining('1 นาที 30 วินาที'), findsOneWidget);
        expect(find.textContaining('คลังคำศัพท์ในเครื่อง'), findsNothing);
        await tester.ensureVisible(find.text('ปรับตัวเลือก'));
        await tester.tap(find.text('ปรับตัวเลือก'));
        await tester.pump();
        final field = tester.widget<DropdownButtonFormField<SessionDirection>>(
          find.byKey(const ValueKey('session-direction')),
        );
        expect(field.initialValue, expected.direction);
        await tester.ensureVisible(
          find.byKey(const ValueKey('session-direction')),
        );
        await tester.tap(find.byKey(const ValueKey('session-direction')));
        await tester.pumpAndSettle();
        expect(find.text('ย้อนทิศทาง'), findsNothing);
        expect(find.text('สลับทิศทาง'), findsNothing);
      },
    );
  }

  testWidgets('semantic close cancels and restores the launching focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final launchFocus = FocusNode();
      addTearDown(launchFocus.dispose);
      var returned = false;
      SessionConfiguration? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                focusNode: launchFocus,
                onPressed: () async {
                  result = await showSessionConfigurationSheet(
                    context: context,
                    registration: registration,
                    policy: policy,
                    limits: limits,
                    ownerId: 'owner:close',
                    packs: const [],
                  );
                  returned = true;
                },
                child: const Text('เปิดกิจกรรม'),
              ),
            ),
          ),
        ),
      );
      launchFocus.requestFocus();
      await tester.pump();
      await tester.tap(find.text('เปิดกิจกรรม'));
      await tester.pumpAndSettle();
      final close = find.bySemanticsLabel('ปิดการตั้งค่าก่อนเริ่มเรียน');
      expect(
        tester
            .getSemantics(close)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      tester.semantics.performAction(
        find.semantics.byLabel('ปิดการตั้งค่าก่อนเริ่มเรียน'),
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionConfigurationSheet), findsNothing);
      expect(returned, isTrue);
      expect(result, isNull);
      expect(launchFocus.hasFocus, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('compact summary starts the exact validated defaults', (
    tester,
  ) async {
    SessionConfiguration? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showSessionConfigurationSheet(
                  context: context,
                  registration: registration,
                  policy: policy,
                  limits: limits,
                  ownerId: 'owner:quickstart',
                  packs: const [
                    SessionConfigurationPackOption(
                      identity: pack,
                      label: 'ชุดฝึกจริง',
                    ),
                  ],
                );
              },
              child: const Text('เปิดกิจกรรม'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดกิจกรรม'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('ชุดฝึกจริง'), findsOneWidget);
    expect(find.textContaining('10 นาที'), findsOneWidget);
    final start = find.byKey(const ValueKey('session-config-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    final expected = policy.validate(
      draft: policy
          .defaultsFor(registration: registration, limits: limits)
          .copyWith(packIdentity: pack),
      registration: registration,
      limits: limits,
      ownerId: 'owner:quickstart',
      availablePackIdentities: const [pack],
    );
    expect(result!.stableSerialization, expected.stableSerialization);
  });

  testWidgets('disclosure keeps edited options and previews policy clamping', (
    tester,
  ) async {
    SessionConfiguration? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showSessionConfigurationSheet(
                  context: context,
                  registration: registration,
                  policy: policy,
                  limits: limits,
                  ownerId: 'owner:disclosure',
                  packs: const [
                    SessionConfigurationPackOption(
                      identity: pack,
                      label: 'ชุดฝึกจริง',
                    ),
                  ],
                );
              },
              child: const Text('เปิดกิจกรรม'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดกิจกรรม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปรับตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-item-count')),
      '99',
    );
    final time = find.byKey(const ValueKey('session-time-limit-seconds'));
    await tester.ensureVisible(time);
    await tester.enterText(time, '90');
    tester.testTextInput.hide();
    await tester.pump();
    final toggle = find.byKey(const ValueKey('session-options-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('12 ข้อ'), findsWidgets);
    expect(find.textContaining('1 นาที 30 วินาที'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('session-item-count')))
          .controller!
          .text,
      '99',
    );
    final untimed = find.byKey(const ValueKey('session-timing-untimed'));
    await tester.ensureVisible(untimed);
    await tester.tap(untimed);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('15 นาที'), findsOneWidget);
    final start = find.byKey(const ValueKey('session-config-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(result!.itemCount, 12);
    expect(result!.timing.maximumActiveEffort, const Duration(seconds: 900));
  });

  testWidgets('Thai configuration remains usable at 200 percent on a phone', (
    tester,
  ) async {
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
        home: Scaffold(
          body: SessionConfigurationSheet(
            registration: registration,
            policy: policy,
            limits: limits,
            ownerId: 'owner:large-text',
            packs: const [],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ปรับตัวเลือก'));
    await tester.tap(find.text('ปรับตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('session-direction')));
    await tester.tap(find.byKey(const ValueKey('session-direction')));
    await tester.pumpAndSettle();
    expect(find.text('ย้อนทิศทาง'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ย้อนทิศทาง'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('session-config-start')),
    );
    await tester.pump();
    expect(find.text('เริ่มเรียน').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sheet exposes labelled bounded controls and returns policy output',
    (tester) async {
      SessionConfiguration? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showSessionConfigurationSheet(
                    context: context,
                    registration: registration,
                    policy: policy,
                    limits: limits,
                    ownerId: 'owner:sheet',
                    packs: const <SessionConfigurationPackOption>[
                      SessionConfigurationPackOption(
                        identity: pack,
                        label: 'Starter pack revision 2',
                      ),
                    ],
                  );
                },
                child: const Text('Configure'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ปรับตัวเลือก'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('ตั้งค่ากิจกรรมการเรียน'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-item-count')), findsOneWidget);
      expect(find.text('ตั้งค่าก่อนเริ่มเรียน'), findsOneWidget);
      expect(find.text('จำนวนข้อ'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-direction')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-difficulty')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-hint-budget')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-time-limit-seconds')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-pack')), findsOneWidget);
      expect(find.text('Starter pack revision 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('session-item-count')),
        '99',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-timing-untimed')),
      );
      await tester.tap(find.byKey(const ValueKey('session-timing-untimed')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('session-time-limit-seconds')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.itemCount, 12);
      expect(result!.packIdentity, pack);
      expect(result!.timing.isUntimedAlternative, isTrue);
      expect(result!.timing.maximumActiveEffort, const Duration(seconds: 900));

      result = null;
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปรับตัวเลือก'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-time-limit-seconds')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('session-time-limit-seconds')),
        '9999',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.timing.timedLimit, const Duration(seconds: 1200));
    },
  );

  testWidgets(
    'stale initial value fails closed with an accessible reset prompt',
    (tester) async {
      final initial = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(packIdentity: pack),
        registration: registration,
        limits: limits,
        ownerId: 'owner:sheet',
        availablePackIdentities: const <ContentIdentity>[pack],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionConfigurationSheet(
              registration: registration,
              policy: policy,
              limits: limits.copyWith(protocolVersion: '2'),
              ownerId: 'owner:sheet',
              packs: const <SessionConfigurationPackOption>[
                SessionConfigurationPackOption(
                  identity: pack,
                  label: 'Starter pack revision 2',
                ),
              ],
              initialConfiguration: initial,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ตั้งค่ากิจกรรมใหม่'), findsOneWidget);
      expect(
        find.text('ขอบเขตการเรียนเปลี่ยนไปหลังจากตั้งค่ากิจกรรมนี้'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-configuration-reset-prompt')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('session-config-reset')));
      await tester.pump();

      expect(find.text('ตั้งค่ากิจกรรมใหม่'), findsNothing);
      expect(
        find.byKey(const ValueKey('session-config-start')),
        findsOneWidget,
      );
    },
  );

  testWidgets('invalid protocol renders a typed reset instead of escaping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionConfigurationSheet(
            registration: registration,
            policy: policy,
            limits: limits.copyWith(maximumItemCount: 0),
            ownerId: 'owner:sheet',
            packs: const <SessionConfigurationPackOption>[],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text('ไม่สามารถอ่านขอบเขตการเรียนที่บันทึกไว้ได้'),
      findsOneWidget,
    );
  });

  testWidgets('typed reset remains reachable in a short lesson viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            height: 128,
            child: SessionConfigurationResetPrompt(
              error: const SessionConfigurationResetRequired(
                SessionConfigurationResetReason.tampered,
              ),
              onReset: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final reset = find.byKey(const ValueKey('session-config-reset'));
    await tester.ensureVisible(reset);
    await tester.pump();
    expect(reset, findsOneWidget);
  });
}
