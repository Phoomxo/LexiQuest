import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/progress/presentation/progress_host_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'owner ABA clears rows immediately and rejects the old pending read',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      final pending = <Completer<ProgressSnapshot>>[];
      final binding = ProgressHostBinding(
        progress: null,
        loader: () {
          final next = Completer<ProgressSnapshot>();
          pending.add(next);
          return next.future;
        },
        ownerChanges: owners.stream,
        visible: () => true,
      );
      owners.add('owner-a');
      final oldRead = binding.readEpoch;
      owners.add(null);
      owners.add('owner-a');
      expect(binding.isReadCurrent(oldRead), isFalse);
      pending.last.complete(_snapshot(2));
      await Future<void>.delayed(Duration.zero);
      expect(binding.snapshot?.totalXp, 2);
      pending.first.complete(_snapshot(999));
      await Future<void>.delayed(Duration.zero);
      expect(binding.snapshot?.totalXp, 2);
      owners.add(null);
      expect(binding.snapshot, isNull);
      expect(binding.loading, isFalse);
      binding.dispose();
      await owners.close();
    },
  );

  test(
    'own cover clears read rows while only its separate launch survives',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      var visible = true;
      var reads = 0;
      final binding = ProgressHostBinding(
        progress: null,
        loader: () async => _snapshot(++reads),
        ownerChanges: owners.stream,
        visible: () => visible,
      );
      owners.add('owner-a');
      await Future<void>.delayed(Duration.zero);
      final read = binding.readEpoch;
      final launch = binding.beginLaunch(read)!;
      expect(binding.snapshot, isNull);
      expect(binding.isReadCurrent(read), isFalse);
      visible = false;
      binding.syncVisibility(ownedCover: true);
      expect(binding.isLaunchCurrent(launch, 'owner-a'), isTrue);
      binding.invalidateLaunch();
      expect(binding.isLaunchCurrent(launch, 'owner-a'), isFalse);
      visible = true;
      binding.syncVisibility(ownedCover: false);
      await Future<void>.delayed(Duration.zero);
      expect(binding.snapshot?.totalXp, 2);
      expect(binding.isReadCurrent(read), isFalse);
      binding.dispose();
      await owners.close();
    },
  );

  test(
    'refresh errors drop prior rows and stream end invalidates launches',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      var fail = false;
      final binding = ProgressHostBinding(
        progress: null,
        loader: () async {
          if (fail) throw StateError('synthetic read failure');
          return _snapshot(3);
        },
        ownerChanges: owners.stream,
        visible: () => true,
      );
      owners.add('owner-a');
      await Future<void>.delayed(Duration.zero);
      final generation = binding.launchGeneration;
      fail = true;
      binding.refresh();
      expect(binding.snapshot, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(binding.readFailed, isTrue);
      expect(binding.snapshot, isNull);
      await owners.close();
      expect(binding.ownerId, isNull);
      expect(binding.isLaunchCurrent(generation, 'owner-a'), isFalse);
      binding.dispose();
    },
  );

  test(
    'a foreign cover clears data even when no host launch preceded it',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      var visible = true;
      final binding = ProgressHostBinding(
        progress: null,
        loader: () async => _snapshot(17),
        ownerChanges: owners.stream,
        visible: () => visible,
      );
      owners.add('owner-a');
      await Future<void>.delayed(Duration.zero);
      expect(binding.snapshot?.totalXp, 17);
      final epoch = binding.readEpoch;
      final launch = binding.launchGeneration;
      visible = false;
      binding.syncVisibility(ownedCover: false);
      expect(binding.snapshot, isNull);
      expect(binding.isReadCurrent(epoch), isFalse);
      expect(binding.isLaunchCurrent(launch, 'owner-a'), isFalse);
      binding.dispose();
      await owners.close();
    },
  );

  test(
    'an independent hub can open after a failed projection, but row actions cannot',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      final binding = ProgressHostBinding(
        progress: null,
        loader: () async => throw StateError('synthetic projection failure'),
        ownerChanges: owners.stream,
        visible: () => true,
      );
      owners.add('owner-a');
      await Future<void>.delayed(Duration.zero);
      expect(binding.readFailed, isTrue);
      expect(binding.beginLaunch(binding.readEpoch), isNull);
      final launch = binding.beginLaunch(
        binding.readEpoch,
        requireSnapshot: false,
      );
      expect(launch, isNotNull);
      owners.add(null);
      expect(binding.isLaunchCurrent(launch!, 'owner-a'), isFalse);
      expect(
        binding.beginLaunch(binding.readEpoch, requireSnapshot: false),
        isNull,
      );
      binding.dispose();
      await owners.close();
    },
  );

  test(
    'blank owner events cannot authorize a loader or an independent launch',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      var reads = 0;
      final binding = ProgressHostBinding(
        progress: null,
        loader: () async => _snapshot(++reads),
        ownerChanges: owners.stream,
        visible: () => true,
      );
      owners.add('  ');
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      expect(binding.snapshot, isNull);
      expect(binding.ownerId, isNull);
      expect(
        binding.beginLaunch(binding.readEpoch, requireSnapshot: false),
        isNull,
      );
      binding.dispose();
      await owners.close();
    },
  );

  test('no observed owner never invokes the test loader', () async {
    var reads = 0;
    final binding = ProgressHostBinding(
      progress: null,
      loader: () async => _snapshot(++reads),
      ownerChanges: null,
      visible: () => true,
    );
    binding.syncVisibility(ownedCover: false);
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 0);
    expect(binding.snapshot, isNull);
    binding.dispose();
  });
}

ProgressSnapshot _snapshot(int xp) => ProgressSnapshot(
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: xp,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: const [],
  weaknesses: const [],
  recommendations: const [],
);
