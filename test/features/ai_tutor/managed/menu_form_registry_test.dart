import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';

void main() {
  test(
    'typed form validates fields, waits for result and replays by payload',
    () async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      var effects = 0;
      registry.registerForm(
        id: 'fill',
        label: 'fill',
        fields: {'word': 5},
        available: () => true,
        invoke: (values) async {
          effects++;
          return {'status': 'filled', 'word': values['word']};
        },
      );
      final snapshot = registry.snapshot();
      expect((snapshot['actions'] as List).single['fields'], {'word': 5});
      final rev = snapshot['revision'] as int;
      Future<Map<String, Object?>> run(
        String request,
        Map<String, String> values,
      ) => registry.execute(
        id: 'fill',
        owner: 'a',
        revision: rev,
        requestId: request,
        values: values,
      );
      expect((await run('missing', {}))['status'], 'invalid');
      expect(
        (await run('extra', {'word': 'book', 'path': 'x'}))['status'],
        'invalid',
      );
      expect((await run('long', {'word': 'abcdef'}))['status'], 'invalid');
      expect(effects, 0);
      final result = await run('one', {'word': 'book'});
      expect(result, {'id': 'fill', 'status': 'filled', 'word': 'book'});
      expect(await run('one', {'word': 'book'}), result);
      expect((await run('one', {'word': 'bag'}))['status'], 'conflict');
      expect(effects, 1);
    },
  );
  test(
    'late form result after session invalidation cannot expose saved data',
    () async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      final done = Completer<Map<String, Object?>>();
      registry.registerForm(
        id: 'save',
        label: 'save',
        fields: {},
        available: () => true,
        invoke: (_) => done.future,
      );
      final pending = registry.execute(
        id: 'save',
        owner: 'a',
        revision: registry.snapshot()['revision'] as int,
        requestId: 'save1',
      );
      registry.invalidateSession();
      done.complete({'status': 'saved', 'private': 'old data'});
      expect(await pending, {'id': 'save', 'status': 'stale'});
      expect(registry.snapshot()['recentActions'], isEmpty);
    },
  );
  test('ordinary navigation rejects supplied form fields', () async {
    final registry = MenuActionRegistry(currentOwner: () => 'a');
    var effects = 0;
    registry.register(
      id: 'open',
      label: 'open',
      available: () => true,
      invoke: () {
        effects++;
      },
    );
    expect(
      (await registry.execute(
        id: 'open',
        owner: 'a',
        revision: registry.snapshot()['revision'] as int,
        requestId: 'bad',
        values: {'word': 'book'},
      ))['status'],
      'invalid',
    );
    expect(effects, 0);
  });
}
