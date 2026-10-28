import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/resource_disposer_stack.dart';

void main() {
  test(
    'disposes in reverse order and continues after a disposer throws',
    () async {
      final calls = <String>[];
      final resources = ResourceDisposerStack();
      resources.own(() => calls.add('first'));
      resources.own(() {
        calls.add('middle');
        throw StateError('middle failed');
      });
      resources.own(() async => calls.add('last'));

      await expectLater(resources.dispose(), throwsStateError);

      expect(calls, ['last', 'middle', 'first']);
    },
  );
}
