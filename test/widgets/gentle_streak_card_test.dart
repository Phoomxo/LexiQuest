import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/widgets/gentle_streak_card.dart';

const _steady = GentleStreakSnapshot(
  ownerId: 'owner-card',
  currentStreakDays: 4,
  longestStreakDays: 7,
  freezeCount: 1,
  phase: GentleStreakPhase.steady,
  policyVersion: StreakPolicy.version,
);

const _empty = GentleStreakSnapshot(
  ownerId: 'owner-card',
  currentStreakDays: 0,
  longestStreakDays: 0,
  freezeCount: 0,
  phase: GentleStreakPhase.empty,
  policyVersion: StreakPolicy.version,
);

const _recovery = GentleStreakSnapshot(
  ownerId: 'owner-card',
  currentStreakDays: 4,
  longestStreakDays: 7,
  freezeCount: 0,
  phase: GentleStreakPhase.recovery,
  policyVersion: StreakPolicy.version,
);

void main() {
  testWidgets('ready card exposes one calm accessible summary', (tester) async {
    await tester.pumpWidget(_app(const GentleStreakCard(snapshot: _steady)));

    expect(find.text('4 learning days'), findsOneWidget);
    expect(find.text('Your best is 7 days.'), findsOneWidget);
    expect(find.text('1 gentle freeze available.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Gentle streak, 4 learning days. Your best is 7 days. '
        '1 gentle freeze available.',
      ),
      findsOneWidget,
    );
    _expectNoPunitiveCopy(tester);
  });

  testWidgets('empty loading error and paused states use calm copy', (
    tester,
  ) async {
    final cases = <Widget>[
      const GentleStreakCard(snapshot: _empty),
      const GentleStreakCard.loading(),
      const GentleStreakCard.error(),
      const GentleStreakCard.paused(snapshot: _steady),
    ];

    for (final card in cases) {
      await tester.pumpWidget(_app(card));
      await tester.pump();
      _expectNoPunitiveCopy(tester);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      _app(const GentleStreakCard.paused(snapshot: _steady)),
    );
    expect(find.text('Your learning rhythm is resting.'), findsOneWidget);
    expect(find.text('Continue whenever you feel ready.'), findsOneWidget);
  });

  testWidgets('recovery prompt is optional and encouraging', (tester) async {
    var continued = false;
    await tester.pumpWidget(
      _app(
        GentleStreakCard(
          snapshot: _recovery,
          onRecovery: () => continued = true,
        ),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('A fresh learning day is ready when you are.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Continue gently'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Continue gently'));
    expect(continued, isTrue);
    _expectNoPunitiveCopy(tester);
  });

  testWidgets('emergency off hides card and recovery prompt', (tester) async {
    await tester.pumpWidget(
      _app(
        GentleStreakCard(
          snapshot: _recovery,
          enabled: false,
          onRecovery: () {},
        ),
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(find.bySemanticsLabel('Continue gently'), findsNothing);
    expect(find.text('Welcome back'), findsNothing);

    await tester.pumpWidget(
      _app(GentleStreakCard(snapshot: _recovery, onRecovery: () {})),
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Your best is 7 days.'), findsOneWidget);
  });

  testWidgets('large text fits a narrow screen without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
        child: _app(GentleStreakCard(snapshot: _recovery, onRecovery: () {})),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Continue gently'), findsOneWidget);
  });
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _expectNoPunitiveCopy(WidgetTester tester) {
  final copy = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .join(' ')
      .toLowerCase();
  for (final term in const <String>[
    'lost',
    'broken',
    'failed',
    'punishment',
    'penalty',
    'reset',
    'buy',
    'coins',
    'xp',
  ]) {
    expect(copy, isNot(contains(term)), reason: 'copy must not contain $term');
  }
}
