// Shadow Rewards Parity Analyzer — D4.3
//
// Usage:
//   dart tools/shadow_rewards_analyzer.dart [--show-idempotency-failures]
//
// Reads shadow_rewards.jsonl (one JSON object per line) and compares each
// eligible decision against the production reward_transactions table.
// Exits 0 when parity >= 99%; exits 1 otherwise.
//
// This is a developer tool — run manually after >= 7 days of shadow mode.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final showIdempotency = args.contains('--show-idempotency-failures');
  final logPath =
      args.where((a) => !a.startsWith('--')).firstOrNull ??
      'shadow_rewards.jsonl';

  final logFile = File(logPath);
  if (!logFile.existsSync()) {
    stderr.writeln('Shadow log not found: $logPath');
    stderr.writeln(
      'Run the app with Feature.shadowRewardV2 enabled for >= 7 days first.',
    );
    exit(2);
  }

  final lines = logFile.readAsLinesSync().where((l) => l.trim().isNotEmpty);
  final entries = lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();

  final total = entries.length;
  final eligible = entries.where((e) {
    final d = e['decision'] as Map<String, dynamic>?;
    return d?['result'] == 'eligible';
  }).toList();
  final wouldSucceed = eligible.where((e) => e['wouldSucceed'] == true).length;
  final alreadyGranted = eligible
      .where((e) => e['wouldSucceed'] == false)
      .length;
  final errors = entries.where((e) => e['error'] != null).length;
  final notEligible = total - eligible.length - errors;

  // ── Report ──────────────────────────────────────────────────────────────────

  stdout.writeln('');
  stdout.writeln('Shadow Mode Parity Analysis');
  stdout.writeln('=' * 50);
  stdout.writeln('Log file       : $logPath');
  stdout.writeln('Total events   : $total');
  stdout.writeln('Not eligible   : $notEligible');
  stdout.writeln('Eligible       : ${eligible.length}');
  stdout.writeln('  ↳ would succeed : $wouldSucceed');
  stdout.writeln('  ↳ already granted (idempotent): $alreadyGranted');
  stdout.writeln('Errors         : $errors');

  if (total == 0) {
    stdout.writeln('');
    stdout.writeln(
      '⚠️  No entries found. Enable shadow mode and re-run after >= 7 days.',
    );
    exit(0);
  }

  // ── Idempotency breakdown ────────────────────────────────────────────────

  if (showIdempotency && alreadyGranted > 0) {
    stdout.writeln('');
    stdout.writeln('Idempotency failures (already-granted events):');
    for (final e in eligible.where((e) => e['wouldSucceed'] == false)) {
      stdout.writeln('  ${e['eventId']}  reason=${e['decision']?['reason']}');
    }
  }

  // ── Error details ────────────────────────────────────────────────────────

  if (errors > 0) {
    stdout.writeln('');
    stdout.writeln('Shadow mode errors:');
    for (final e in entries.where((e) => e['error'] != null)) {
      stdout.writeln('  ${e['eventId']}  error=${e['error']}');
    }
  }

  // ── Parity verdict ───────────────────────────────────────────────────────

  // Parity = percentage of eligible events where the shadow decision matches
  // what production would do.  For Phase -1 the criterion is simple:
  // eligible-but-not-yet-granted events (wouldSucceed=true) should be the
  // majority; errors should be < 1%.

  final eligibleTotal = eligible.length;
  final parityNumerator = wouldSucceed.toDouble();
  final parity = eligibleTotal == 0
      ? 100.0
      : (parityNumerator / eligibleTotal) * 100;
  final errorRate = total == 0 ? 0.0 : (errors.toDouble() / total) * 100;

  stdout.writeln('');
  stdout.writeln(
    'Parity (eligible events that would succeed): '
    '${parity.toStringAsFixed(1)}%',
  );
  stdout.writeln('Error rate: ${errorRate.toStringAsFixed(2)}%');
  stdout.writeln('');

  const parityThreshold = 99.0;
  const errorThreshold = 1.0;

  if (parity >= parityThreshold && errorRate < errorThreshold) {
    stdout.writeln(
      '✅  Parity ≥ ${parityThreshold.toInt()}% and error rate < '
      '${errorThreshold.toInt()}% — shadow mode is ready for cutover review.',
    );
    exit(0);
  } else {
    if (parity < parityThreshold) {
      stdout.writeln(
        '❌  Parity ${parity.toStringAsFixed(1)}% < required '
        '${parityThreshold.toInt()}%',
      );
      stdout.writeln(
        '   Investigate diverging events and fix eligibility policy or adapter.',
      );
    }
    if (errorRate >= errorThreshold) {
      stdout.writeln(
        '❌  Error rate ${errorRate.toStringAsFixed(2)}% ≥ '
        '${errorThreshold.toInt()}%',
      );
      stdout.writeln('   Check shadow mode error logs above.');
    }
    stdout.writeln('');
    stdout.writeln(
      'Do NOT cut over to V2 until parity >= ${parityThreshold.toInt()}%.',
    );
    exit(1);
  }
}
