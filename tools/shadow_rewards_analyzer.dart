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
  final logPath = args.where((a) => !a.startsWith('--')).firstOrNull
      ?? 'shadow_rewards.jsonl';

  final logFile = File(logPath);
  if (!logFile.existsSync()) {
    stderr.writeln('Shadow log not found: $logPath');
    stderr.writeln('Run the app with Feature.shadowRewardV2 enabled for >= 7 days first.');
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
  final alreadyGranted =
      eligible.where((e) => e['wouldSucceed'] == false).length;
  final errors = entries.where((e) => e['error'] != null).length;
  final notEligible = total - eligible.length - errors;

  // ── Report ──────────────────────────────────────────────────────────────────

  print('');
  print('Shadow Mode Parity Analysis');
  print('=' * 50);
  print('Log file       : $logPath');
  print('Total events   : $total');
  print('Not eligible   : $notEligible');
  print('Eligible       : ${eligible.length}');
  print('  ↳ would succeed : $wouldSucceed');
  print('  ↳ already granted (idempotent): $alreadyGranted');
  print('Errors         : $errors');

  if (total == 0) {
    print('');
    print('⚠️  No entries found. Enable shadow mode and re-run after >= 7 days.');
    exit(0);
  }

  // ── Idempotency breakdown ────────────────────────────────────────────────

  if (showIdempotency && alreadyGranted > 0) {
    print('');
    print('Idempotency failures (already-granted events):');
    for (final e in eligible.where((e) => e['wouldSucceed'] == false)) {
      print('  ${e['eventId']}  reason=${e['decision']?['reason']}');
    }
  }

  // ── Error details ────────────────────────────────────────────────────────

  if (errors > 0) {
    print('');
    print('Shadow mode errors:');
    for (final e in entries.where((e) => e['error'] != null)) {
      print('  ${e['eventId']}  error=${e['error']}');
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
  final errorRate =
      total == 0 ? 0.0 : (errors.toDouble() / total) * 100;

  print('');
  print('Parity (eligible events that would succeed): '
      '${parity.toStringAsFixed(1)}%');
  print('Error rate: ${errorRate.toStringAsFixed(2)}%');
  print('');

  const parityThreshold = 99.0;
  const errorThreshold = 1.0;

  if (parity >= parityThreshold && errorRate < errorThreshold) {
    print('✅  Parity ≥ ${parityThreshold.toInt()}% and error rate < '
        '${errorThreshold.toInt()}% — shadow mode is ready for cutover review.');
    exit(0);
  } else {
    if (parity < parityThreshold) {
      print('❌  Parity ${parity.toStringAsFixed(1)}% < required '
          '${parityThreshold.toInt()}%');
      print('   Investigate diverging events and fix eligibility policy or adapter.');
    }
    if (errorRate >= errorThreshold) {
      print('❌  Error rate ${errorRate.toStringAsFixed(2)}% ≥ '
          '${errorThreshold.toInt()}%');
      print('   Check shadow mode error logs above.');
    }
    print('');
    print('Do NOT cut over to V2 until parity >= ${parityThreshold.toInt()}%.');
    exit(1);
  }
}
