import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  for (final replacement in ['B', 'missing ports', 'removed']) {
    testWidgets('Score A artifacts disappear after Scope $replacement', (
      tester,
    ) async {
      final harness = _ScoreHarness();
      await harness.open(tester, _dependencies('A'));
      _expectPrivateScore();

      await harness.replaceScope(tester, replacement);

      _expectNoPrivateScore();
      expect(harness.repairs, 0);
      expect(harness.navigatorKey.currentState!.canPop(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'retained Score repair cannot delegate after Scope $replacement',
      (tester) async {
        final harness = _ScoreHarness();
        await harness.open(tester, _dependencies('A'));
        final repair = _buttonCallback(tester, 'ฝึกคำที่ผิด (1)');
        await harness.replaceScope(tester, replacement);

        repair();
        await tester.pumpAndSettle();

        expect(harness.repairs, 0);
        expect(find.byType(ScoreScreen), findsOneWidget);
        _expectNoPrivateScore();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'retained Score return cannot pop a route after Scope $replacement',
      (tester) async {
        final harness = _ScoreHarness();
        await harness.open(tester, _dependencies('A'));
        final back = _buttonCallback(tester, 'กลับชุด private A');
        await harness.replaceScope(tester, replacement);
        harness.navigatorKey.currentState!
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('current route')),
              ),
            )
            .ignore();
        await tester.pumpAndSettle();

        back();
        await tester.pumpAndSettle();

        expect(find.text('current route'), findsOneWidget);
        expect(harness.repairs, 0);
        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsOneWidget);
        _expectNoPrivateScore();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('standalone Score keeps its existing repair and return actions', (
    tester,
  ) async {
    final harness = _ScoreHarness();
    await harness.open(tester, null);
    _expectPrivateScore();
    final repair = _buttonCallback(tester, 'ฝึกคำที่ผิด (1)');
    final back = _buttonCallback(tester, 'กลับชุด private A');

    repair();
    await tester.pump();
    expect(harness.repairs, 1);
    expect(find.byType(ScoreScreen), findsOneWidget);
    back();
    await tester.pumpAndSettle();
    expect(find.text('root route'), findsOneWidget);
    expect(find.byType(ScoreScreen), findsNothing);
    expect(harness.navigatorKey.currentState!.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

VoidCallback _buttonCallback(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first,
    )
    .onPressed!;

void _expectPrivateScore() {
  expect(
    find.byKey(const ValueKey('score-session:session-private-A')),
    findsOneWidget,
  );
  expect(find.text('ชุด private A'), findsOneWidget);
  expect(find.text('private-a'), findsOneWidget);
  expect(find.text('ความหมาย private A'), findsOneWidget);
  expect(find.text('67%'), findsOneWidget);
}

void _expectNoPrivateScore() {
  expect(
    find.byKey(const ValueKey('score-session:session-private-A')),
    findsNothing,
  );
  expect(find.text('ชุด private A'), findsNothing);
  expect(find.text('private-a'), findsNothing);
  expect(find.text('ความหมาย private A'), findsNothing);
  expect(find.text('67%'), findsNothing);
  expect(find.text('ตอบถูก'), findsNothing);
  expect(find.text('คำที่ควรฝึกต่อ'), findsNothing);
  expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
  expect(find.text('กลับชุด private A'), findsNothing);
}

final class _ScoreHarness {
  final navigatorKey = GlobalKey<NavigatorState>();
  late final app = MaterialApp(
    key: GlobalKey(),
    navigatorKey: navigatorKey,
    home: const Scaffold(body: Text('root route')),
  );
  var repairs = 0;

  Widget _root(AppDependencies? dependencies) => dependencies == null
      ? app
      : AppDependenciesScope(dependencies: dependencies, child: app);

  Future<void> open(WidgetTester tester, AppDependencies? dependencies) async {
    await tester.pumpWidget(_root(dependencies));
    navigatorKey.currentState!
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ScoreScreen(
              correctAnswers: 2,
              wrongAnswers: 1,
              score: 67,
              categoryName: 'ชุด private A',
              sessionId: 'session-private-A',
              returnLabel: 'กลับชุด private A',
              mistakes: const [
                QuizWord(
                  id: 'word-private-A',
                  categoryId: 'category-private-A',
                  spelling: 'private-a',
                  meaning: 'ความหมาย private A',
                  partOfSpeech: 'noun',
                ),
              ],
              onPracticeMistakes: () => repairs++,
            ),
          ),
        )
        .ignore();
    await tester.pumpAndSettle();
  }

  Future<void> replaceScope(WidgetTester tester, String replacement) async {
    final navigator = navigatorKey.currentState;
    final score = tester.element(find.byType(ScoreScreen));
    final dependencies = replacement == 'removed'
        ? null
        : _dependencies(replacement == 'B' ? 'B' : null);
    await tester.pumpWidget(_root(dependencies));
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState, same(navigator));
    expect(tester.element(find.byType(ScoreScreen)), same(score));
  }
}

AppDependencies _dependencies(String? ownerId) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _GuestSession(),
  localOwners: ownerId == null ? null : _Owners(ownerId),
);

final class _GuestSession extends Fake implements GuestSessionService {}

final class _Owners extends Fake implements LocalOwnerRepository {
  _Owners(this.id);
  final String id;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 11, 14));
}
