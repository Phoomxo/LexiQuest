import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  testWidgets(
    'owner-bound context admits late AI without rebuilding and retires on account switch',
    (tester) async {
      String? owner;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: const MaterialApp(
            home: MenuActionBinding(
              id: 'target',
              label: 'book',
              ownerId: 'a',
              readValue: 'word-a',
              onInvoke: null,
              child: Text('existing dialog'),
            ),
          ),
        ),
      );
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'a';
      registry.invalidateSession(preserveContext: true);
      expect(
        (registry.snapshot()['context'] as List).single['value'],
        'word-a',
      );
      owner = null;
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'a';
      expect(
        (registry.snapshot()['context'] as List).single['value'],
        'word-a',
      );
      owner = 'b';
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'a';
      expect(registry.snapshot()['context'], isEmpty);
    },
  );

  testWidgets('long user labels stay bounded without changing native text', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'a');
    final label = List.filled(120, '📚').join();
    var invoked = false;
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MenuActionBinding(
                    id: 'action',
                    label: label,
                    onInvoke: () => invoked = true,
                    child: Text(label),
                  ),
                  MenuActionBinding(
                    id: 'context',
                    label: label,
                    onInvoke: null,
                    readValue: 'target-id',
                    child: const SizedBox.shrink(),
                  ),
                  MenuActionBinding(
                    id: 'form',
                    label: label,
                    onInvoke: null,
                    onForm: (_) => {'status': 'filled'},
                    child: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final snapshot = registry.snapshot();
    for (final item in [
      ...snapshot['actions'] as List,
      ...snapshot['context'] as List,
    ]) {
      expect((item['label'] as String).length, lessThanOrEqualTo(200));
      expect((item['label'] as String).runes, isNot(contains(0xfffd)));
    }
    expect(find.text(label), findsOneWidget);
    expect(
      (await registry.execute(
        id: 'action',
        owner: 'a',
        revision: snapshot['revision'] as int,
        requestId: 'long-label',
      ))['status'],
      'invoked',
    );
    expect(invoked, isTrue);
  });

  testWidgets(
    'route context covers canonical child routes without private arguments',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [MenuRouteObserver(registry)],
          home: const Scaffold(),
        ),
      );
      for (final id in NavigationGlossary.hubChildRouteIds) {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: id,
              arguments: {'email': 'private@example.test'},
            ),
            builder: (_) => const Scaffold(),
          ),
        );
        await tester.pumpAndSettle();
        final context = registry.snapshot()['context'] as List;
        expect(context.single['id'], id);
        expect(context.toString(), isNot(contains('private@example.test')));
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(registry.snapshot()['context'], isEmpty);
      }
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'private@example.test'),
          builder: (_) => const Scaffold(),
        ),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
    },
  );
  testWidgets(
    'mounted control shares its callback and disappears under a route',
    (tester) async {
      var count = 0;
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: MenuActionBinding(
                id: 'test',
                label: 'ทดสอบ',
                onInvoke: () {
                  count++;
                },
                child: TextButton(
                  onPressed: () {
                    count++;
                  },
                  child: const Text('ทดสอบ'),
                ),
              ),
            ),
          ),
        ),
      );
      final snapshot = registry.snapshot();
      await registry.execute(
        id: 'test',
        owner: 'a',
        revision: snapshot['revision'] as int,
        requestId: 'one',
      );
      expect(count, 1);
      await tester.tap(find.text('ทดสอบ'));
      expect(count, 2);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('next')),
        ),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['actions'], isEmpty);
      expect(
        (await registry.execute(
          id: 'test',
          owner: 'a',
          revision: snapshot['revision'] as int,
          requestId: 'two',
        ))['status'],
        'unavailable',
      );
      expect(count, 2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect((registry.snapshot()['actions'] as List).length, 1);
      await tester.pumpWidget(const SizedBox());
      expect(registry.snapshot()['actions'], isEmpty);
    },
  );
  testWidgets('offstage and disabled actions are never advertised', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'a');
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MenuActionBinding(
                  id: 'disabled',
                  label: 'disabled',
                  onInvoke: null,
                  child: Text('disabled'),
                ),
                Offstage(
                  child: MenuActionBinding(
                    id: 'hidden',
                    label: 'hidden',
                    onInvoke: null,
                    child: Text('hidden'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(registry.snapshot()['actions'], isEmpty);
  });
}
