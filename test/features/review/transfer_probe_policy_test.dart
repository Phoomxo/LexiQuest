import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/review/domain/transfer_probe.dart';

void main() {
  final origin = DateTime.utc(2026, 9, 20);
  test('24 hour boundary never admits immediate repair', () {
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.add(const Duration(hours: 24) - Duration(seconds: 1)),
        distinct: true,
      ),
      ProbeTiming.tooEarly,
    );
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.add(const Duration(hours: 24)),
        distinct: true,
      ),
      ProbeTiming.unverified,
    );
  });
  test('same context and backwards clock withhold eligibility', () {
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.add(const Duration(days: 2)),
        distinct: false,
      ),
      ProbeTiming.noDistinctContext,
    );
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.subtract(const Duration(seconds: 1)),
        distinct: true,
      ),
      ProbeTiming.clockUncertain,
    );
  });
  test('wall time alone cannot claim verified delay', () {
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.add(const Duration(days: 365)),
        distinct: true,
      ),
      ProbeTiming.unverified,
    );
    expect(
      TransferProbePolicy.evaluate(
        origin: origin,
        now: origin.add(const Duration(days: 1)),
        distinct: true,
        observedElapsed: const Duration(minutes: 1),
      ),
      ProbeTiming.clockUncertain,
    );
  });
  test('authored probes are distinct from base and one another', () {
    expect(TransferProbeInventory.items.length, 6);
    expect(
      TransferProbeInventory.items.map((e) => e.contextHash).toSet().length,
      6,
    );
    for (final item in TransferProbeInventory.items) {
      expect(item.sentence.contains(item.answer), isTrue);
      expect(item.contextHash, isNot(item.originContextHash));
      expect(item.revision, 1);
    }
  });
}
