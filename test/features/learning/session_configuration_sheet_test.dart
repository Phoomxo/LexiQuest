import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
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

      expect(
        find.bySemanticsLabel('Configure meaning-quiz session'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-item-count')), findsOneWidget);
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

      expect(find.text('Reset session configuration'), findsOneWidget);
      expect(
        find.text(
          'The study protocol changed after this session was configured.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-configuration-reset-prompt')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('session-config-reset')));
      await tester.pump();

      expect(find.text('Reset session configuration'), findsNothing);
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
      find.text('The saved study protocol limits are unavailable.'),
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
