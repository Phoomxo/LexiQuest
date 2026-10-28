import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'pair_matching_evidence_contract_test.dart';

void main() {
  test(
    'full OFF elapsed shares pause leases and preserves submillisecond carry',
    () {
      var micros = 0;
      final clock = PairActiveClock(
        PairTimerState(
          mode: PairTimerMode.off,
          remainingActiveMs: 0,
          interactiveElapsedMs: 0,
        ),
        () => micros,
      );
      clock.resumeInteraction();
      for (var i = 0; i < 10; i++) {
        micros += 500;
        final first = clock.pause(PairPauseReason.modal);
        final second = clock.pause(PairPauseReason.narration);
        micros += 900000;
        clock.release(first);
        clock.release(second);
      }
      expect(clock.value.interactiveElapsedMs, 5);
      expect(clock.value.elapsedActiveMs, 0);
    },
  );
  test('full elapsed caps timeout then continues through the same clock', () {
    var micros = 0;
    final clock = PairActiveClock(
      PairTimerState(
        mode: PairTimerMode.running,
        remainingActiveMs: 1000,
        interactiveElapsedMs: 0,
      ),
      () => micros,
    );
    clock.resumeInteraction();
    micros += 5000000;
    expect(clock.value.interactiveElapsedMs, 1000);
    expect(clock.value.elapsedActiveMs, 1000);
    clock.replace(clock.value.copy(mode: PairTimerMode.continuedUntimed));
    micros += 2000000;
    expect(clock.value.interactiveElapsedMs, 3000);
    expect(clock.value.elapsedActiveMs, 1000);
  });
  test(
    'historical missing coverage stays missing and OFF clock fault stays playable',
    () {
      var micros = 1000;
      final historical = PairActiveClock(
        PairTimerState.initial(PairTimerPreset.off),
        () => micros,
      );
      historical.resumeInteraction();
      micros += 5000000;
      expect(historical.value.interactiveElapsedMs, isNull);
      final measured = PairActiveClock(
        PairTimerState(
          mode: PairTimerMode.off,
          remainingActiveMs: 0,
          interactiveElapsedMs: 0,
        ),
        () => micros,
      );
      measured.resumeInteraction();
      micros = 0;
      expect(measured.value.interactiveElapsedMs, isNull);
      expect(measured.isPaused, isFalse);
    },
  );
  test('repeated submillisecond pauses retain runtime rounding remainder', () {
    var micros = 0;
    final clock = PairActiveClock(
      PairTimerState.initial(PairTimerPreset.seconds60),
      () => micros,
    );
    clock.resumeInteraction();
    for (var i = 0; i < 10; i++) {
      micros += 500;
      final token = clock.pause(PairPauseReason.modal);
      clock.release(token);
    }
    expect(clock.value.elapsedActiveMs, 5);
  });
  test('timer state owns an immutable copy of pause reasons', () {
    final reasons = {PairPauseReason.modal};
    final state = PairTimerState(
      mode: PairTimerMode.running,
      remainingActiveMs: 1000,
      reasons: reasons,
    );
    reasons.clear();
    expect(state.reasons, {PairPauseReason.modal});
    expect(() => state.reasons.clear(), throwsUnsupportedError);
  });
  test(
    'restart spacing counts previously correct other words since failure',
    () {
      final answers = [
        const PairRepairAnswer('0', 'a', true),
        const PairRepairAnswer('1', 'b', true),
        const PairRepairAnswer('2', 'c', false, roundOrdinal: 1),
        const PairRepairAnswer('3', 'a', true, roundOrdinal: 1),
      ];
      var tickets = PairRepairPolicy.project(['a', 'b', 'c', 'd'], answers);
      expect(tickets.single.status, PairRepairStatus.waiting);
      tickets = PairRepairPolicy.project(
        ['a', 'b', 'c', 'd'],
        [...answers, const PairRepairAnswer('4', 'b', true, roundOrdinal: 1)],
      );
      expect(tickets.single.status, PairRepairStatus.available);
    },
  );
  for (final preset in PairTimerPreset.values) {
    test('active time and owned overlapping pause leases $preset', () {
      var micros = 0;
      final clock = PairActiveClock(
        PairTimerState.initial(preset),
        () => micros,
      );
      micros += 9000000;
      expect(clock.value.elapsedActiveMs, 0);
      clock.resumeInteraction();
      micros += 1250000;
      final a = clock.pause(PairPauseReason.modal);
      final b = clock.pause(PairPauseReason.modal);
      final narration = clock.pause(PairPauseReason.narration);
      final elapsed = preset == PairTimerPreset.off ? 0 : 1250;
      expect(clock.value.elapsedActiveMs, elapsed);
      micros += 999000000;
      clock.release(a);
      clock.release(a);
      clock.release(narration);
      expect(clock.isPaused, true);
      clock.release(b);
      micros += 500000;
      expect(
        clock.value.elapsedActiveMs,
        preset == PairTimerPreset.off ? 0 : 1750,
      );
      final other = PairActiveClock(clock.value, () => micros);
      other.release(b);
      expect(other.isPaused, true);
    });
  }
  test('clock rollback preserves accounted time and pauses for recovery', () {
    var micros = 10000;
    final clock = PairActiveClock(
      PairTimerState.initial(PairTimerPreset.seconds60),
      () => micros,
    );
    clock.resumeInteraction();
    micros += 5000000;
    clock.fold();
    micros = 0;
    expect(clock.value.elapsedActiveMs, 5000);
    expect(clock.isPaused, true);
    expect(clock.reasons, contains(PairPauseReason.clockFault));
  });
  test(
    'fresh OFF timer has no elapsed time and no checkpoint tick writes',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      expect(c.timer.remainingActiveMs, 0);
      expect(c.timer.elapsedActiveMs, 0);
      expect(c.timer.mode.name, 'off');
      expect(h.repository.checkpoints, isEmpty);
    },
  );
}
