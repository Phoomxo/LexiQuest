import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/download_counter.dart';

void main() {
  test('persists every successful download event per version', () async {
    final database = AppDatabase(NativeDatabase.memory());
    var event = 0;
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'event-${++event}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(database.close);

    await counter.increment('model-v1');
    await counter.increment('model-v1');
    await counter.increment('model-v2');

    expect(await counter.count('model-v1'), 2);
    expect(await counter.count('model-v2'), 1);
    expect(await counter.count('missing'), 0);
  });

  test('duplicate event id is rejected without inflating the count', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'same-event',
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(database.close);

    await counter.increment('model-v1');
    await expectLater(counter.increment('model-v1'), throwsA(anything));

    expect(await counter.count('model-v1'), 1);
  });
}
