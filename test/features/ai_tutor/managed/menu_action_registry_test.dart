import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';

void main() {
  test(
    'navigation acknowledges invocation before route closes and retains late failures',
    () async {
      final closed = Completer<void>();
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      registry.register(
        id: 'route',
        label: 'หน้าทดสอบ',
        available: () => true,
        invoke: () => closed.future,
        dispatchOnly: true,
      );
      final revision = registry.snapshot()['revision'] as int;
      final invoked = await registry
          .execute(
            id: 'route',
            owner: 'a',
            revision: revision,
            requestId: 'open',
          )
          .timeout(const Duration(milliseconds: 100));
      expect(invoked['status'], 'invoked');
      closed.completeError(StateError('private error'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await registry.execute(
          id: 'route',
          owner: 'a',
          revision: revision,
          requestId: 'open',
        ))['status'],
        'failed',
      );
    },
  );
  test(
    'read-only context is bounded, cannot invoke, and never survives an owner switch',
    () async {
      var owner = 'a';
      final registry = MenuActionRegistry(currentOwner: () => owner);
      registry.registerContext(
        id: 'profile/mastery',
        label: 'ความชำนาญ',
        available: () => true,
        value: () => '3 คำ',
      );
      expect(registry.snapshot()['context'], [
        {'id': 'profile/mastery', 'label': 'ความชำนาญ', 'value': '3 คำ'},
      ]);
      expect(
        (await registry.execute(
          id: 'profile/mastery',
          owner: owner,
          revision: registry.snapshot()['revision'] as int,
          requestId: 'read',
        ))['status'],
        'unavailable',
      );
      owner = 'b';
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'a';
      expect(registry.snapshot()['context'], isEmpty);
    },
  );
  test(
    'inactive duplicate never shadows another active instance of a menu',
    () async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      var calls = 0;
      registry.register(
        id: 'home/vocabulary',
        label: 'คำศัพท์',
        available: () => true,
        invoke: () {
          calls++;
        },
      );
      registry.register(
        id: 'home/vocabulary',
        label: 'คำศัพท์',
        available: () => false,
        invoke: () => fail('closed drawer callback'),
      );
      final snapshot = registry.snapshot();
      expect((snapshot['actions'] as List).length, 1);
      await registry.execute(
        id: 'home/vocabulary',
        owner: 'a',
        revision: snapshot['revision'] as int,
        requestId: 'one',
      );
      expect(calls, 1);
    },
  );
  late String? owner;
  late MenuActionRegistry registry;
  late int effects;
  late bool available;
  setUp(() {
    owner = 'owner-a';
    effects = 0;
    available = true;
    registry = MenuActionRegistry(currentOwner: () => owner);
  });
  void Function() bind() => registry.register(
    id: 'home/learn',
    label: 'เรียน',
    available: () => available,
    invoke: () {
      effects++;
    },
  );
  Future<Map<String, Object?>> execute(int revision, [String request = 'r1']) =>
      registry.execute(
        id: 'home/learn',
        owner: 'owner-a',
        revision: revision,
        requestId: request,
      );
  int revision() => registry.snapshot()['revision'] as int;

  test(
    'advertised action invokes the actual callback exactly once on replay',
    () async {
      bind();
      final rev = revision();
      expect((registry.snapshot()['actions'] as List).single, {
        'id': 'home/learn',
        'label': 'เรียน',
      });
      expect((await execute(rev))['status'], 'invoked');
      expect((await execute(rev))['status'], 'invoked');
      expect(effects, 1);
    },
  );
  test(
    'disabled and unmounted actions cannot execute from an old snapshot',
    () async {
      final unbind = bind();
      final rev = revision();
      available = false;
      expect((await execute(rev))['status'], 'unavailable');
      available = true;
      unbind();
      expect((await execute(rev, 'r2'))['status'], 'stale');
      expect(effects, 0);
    },
  );
  test(
    'owner switch invalidates both actions and cached successful receipts',
    () async {
      bind();
      final rev = revision();
      await execute(rev);
      owner = 'owner-b';
      expect((await execute(rev))['status'], 'stale');
      expect(effects, 1);
    },
  );
  test(
    'replaced callback cannot execute against a previous revision',
    () async {
      final unbind = bind();
      final rev = revision();
      final unbindNew = bind();
      unbind();
      expect((await execute(rev))['status'], 'stale');
      expect((await execute(revision(), 'r2'))['status'], 'invoked');
      unbindNew();
      expect(registry.snapshot()['actions'], isEmpty);
    },
  );
  test(
    'concurrent actions are rejected while an asynchronous callback is pending',
    () async {
      final wait = Completer<void>();
      registry.register(
        id: 'home/learn',
        label: 'เรียน',
        available: () => true,
        invoke: () => wait.future,
      );
      final rev = revision();
      final first = execute(rev);
      expect((await execute(rev, 'r2'))['status'], 'busy');
      wait.complete();
      expect((await first)['status'], 'invoked');
    },
  );
  test(
    'failure is a failed receipt, and replay does not repeat partial effects',
    () async {
      registry.register(
        id: 'home/learn',
        label: 'เรียน',
        available: () => true,
        invoke: () {
          effects++;
          throw StateError('private detail');
        },
      );
      final rev = revision();
      expect(await execute(rev), {'status': 'failed', 'id': 'home/learn'});
      expect((await execute(rev))['status'], 'failed');
      expect(effects, 1);
    },
  );
}
