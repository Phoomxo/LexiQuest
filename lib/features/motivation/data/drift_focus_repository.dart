import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/focus_models.dart';
import '../domain/timezone_policy.dart';
import 'drift_streak_repository.dart';

final class DriftFocusRepository {
  DriftFocusRepository(this.database, {DriftStreakRepository? calendar})
    : calendar = calendar ?? DriftStreakRepository(database);

  final db.AppDatabase database;
  final DriftStreakRepository calendar;

  Future<FocusSnapshot?> load({
    required String ownerId,
    required String id,
  }) async {
    _identifier(ownerId);
    _identifier(id);
    final row =
        await (database.select(database.focusSessions)
              ..where((row) => row.ownerId.equals(ownerId) & row.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _decode(row).snapshot(row);
  }

  Future<FocusSnapshot?> findOpen({required String ownerId}) async {
    _identifier(ownerId);
    final row =
        await (database.select(database.focusSessions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.state.isIn(['running', 'paused']),
            ))
            .getSingleOrNull();
    return row == null ? null : _decode(row).snapshot(row);
  }

  Future<FocusSnapshot> start({
    required String expectedOwnerId,
    required String id,
    required int targetMs,
    required FocusSample sample,
  }) => database.transaction(() async {
    _identifier(id);
    sample.validate();
    if (targetMs < 1 || targetMs > 86400000) {
      throw ArgumentError.value(targetMs, 'targetMs', 'must be within one day');
    }
    final owner = await _owner(expectedOwnerId);
    if (sample.utcMs < owner.createdAtUtcMs) {
      throw StateError('Focus start precedes owner creation');
    }
    final existing = await (database.select(
      database.focusSessions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      final envelope = _decode(existing);
      if (existing.ownerId != expectedOwnerId ||
          existing.originOwnerId != expectedOwnerId ||
          existing.targetMs != targetMs ||
          !_sameSample(envelope.start, sample)) {
        throw StateError('Focus identity already has different evidence');
      }
      return envelope.snapshot(existing);
    }
    if (await findOpen(ownerId: expectedOwnerId) != null) {
      throw StateError('Owner already has an open focus round');
    }
    String? ruleId;
    String? week;
    try {
      final pin = await database.transaction(() async {
        final rule = await calendar.calendarRuleAt(
          ownerId: expectedOwnerId,
          occurredAtUtcMs: sample.utcMs,
        );
        final stored = await (database.select(
          database.ownerCalendarEpochs,
        )..where((row) => row.ruleId.equals(rule.ruleId))).getSingleOrNull();
        if (stored == null ||
            stored.ownerId != expectedOwnerId ||
            stored.originOwnerId != expectedOwnerId ||
            rule.originOwnerId != expectedOwnerId ||
            stored.ianaId != rule.ianaId ||
            stored.tzdbRevision != rule.tzdbRevision ||
            stored.effectiveUtcUs != rule.effectiveUtcUs ||
            stored.expiresUtcUs != rule.expiresUtcUs ||
            rule.tzdbRevision != bundledTzdbRevision) {
          throw StateError('Focus calendar pin is unavailable');
        }
        final window = TimezonePolicy.captureWindow(
          DateTime.fromMillisecondsSinceEpoch(sample.utcMs, isUtc: true),
          rule.ianaId,
          epochEffectiveAtUtc: DateTime.fromMicrosecondsSinceEpoch(
            rule.effectiveUtcUs,
            isUtc: true,
          ),
          epochExpiresAtUtc: rule.expiresUtcUs == null
              ? null
              : DateTime.fromMicrosecondsSinceEpoch(
                  rule.expiresUtcUs!,
                  isUtc: true,
                ),
        );
        if (window.weekMonday.year < 1 || window.weekMonday.year > 9999) {
          throw StateError('Focus civil week is outside the supported range');
        }
        return (
          rule.ruleId,
          window.weekMonday.toIso8601String().substring(0, 10),
        );
      }, requireNew: true);
      ruleId = pin.$1;
      week = pin.$2;
    } on Object {
      // Measured time survives unavailable optional calendar attribution.
    }
    final envelope = _Envelope(
      start: sample,
      open: sample,
      spans: const [],
      step: 'start',
      fromRevision: 0,
      commandSample: sample,
    );
    await database
        .into(database.focusSessions)
        .insert(
          db.FocusSessionsCompanion.insert(
            id: id,
            ownerId: expectedOwnerId,
            originOwnerId: expectedOwnerId,
            targetMs: targetMs,
            startedAtUtcMs: sample.utcMs,
            startRuleId: Value(ruleId),
            startCivilWeek: Value(week),
            state: 'running',
            spansJson: envelope.encode(),
          ),
        );
    return (await load(ownerId: expectedOwnerId, id: id))!;
  });

  Future<FocusSnapshot> transition({
    required String expectedOwnerId,
    required String id,
    required int expectedRevision,
    required FocusStep step,
    required FocusSample sample,
    bool suspendClock = false,
  }) => database.transaction(() async {
    _identifier(id);
    sample.validate();
    if (expectedRevision < 1 || expectedRevision >= 9007199254740991) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision');
    }
    if (suspendClock && step != FocusStep.pause) {
      throw ArgumentError('Only a pause may suspend clock measurement');
    }
    await _owner(expectedOwnerId);
    final row =
        await (database.select(database.focusSessions)..where(
              (row) => row.id.equals(id) & row.ownerId.equals(expectedOwnerId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Owner-scoped focus round not found');
    }
    final previous = _decode(row);
    if (row.revision == expectedRevision + 1 &&
        previous.fromRevision == expectedRevision &&
        previous.step == step.name &&
        previous.suspendClock == suspendClock &&
        _sameSample(previous.commandSample, sample)) {
      return previous.snapshot(row);
    }
    if (row.revision != expectedRevision) {
      throw StateError('Focus revision changed; reload the round');
    }
    final current = previous.snapshot(row);
    if (current.state == FocusState.completed ||
        current.state == FocusState.interrupted) {
      throw StateError('Focus round is already closed');
    }
    final open = previous.open;
    var state = current.state;
    FocusSample? nextOpen;
    int? end;
    final spans = [...previous.spans];
    if (step == FocusStep.recoverInterrupted) {
      if (state != FocusState.running ||
          open!.continuityId == sample.continuityId) {
        throw StateError('No lost running clock to recover');
      }
      state = FocusState.interrupted;
    } else {
      if ((step == FocusStep.pause &&
              state != FocusState.running &&
              !suspendClock) ||
          (step == FocusStep.resume && state != FocusState.paused)) {
        throw StateError('Invalid focus transition');
      }
      if (step == FocusStep.pause &&
          state == FocusState.paused &&
          open == null) {
        return current;
      }
      final sameClock = open?.continuityId == sample.continuityId;
      if ((sameClock && sample.monotonicUs < open!.monotonicUs) ||
          (!sameClock && state == FocusState.running)) {
        throw StateError('Focus clock continuity is unavailable');
      }
      spans.add(
        FocusSpan(
          kind: state == FocusState.running
              ? FocusSpanKind.active
              : FocusSpanKind.paused,
          observedStartUtcMs:
              open?.utcMs ??
              (spans.isEmpty
                  ? previous.start.utcMs
                  : spans.last.observedEndUtcMs),
          observedEndUtcMs: sample.utcMs,
          elapsedUs: sameClock ? sample.monotonicUs - open!.monotonicUs : null,
        ),
      );
      final activeUs = spans
          .where((span) => span.kind == FocusSpanKind.active)
          .fold<int>(0, (total, span) => total + (span.elapsedUs ?? 0));
      if (step == FocusStep.finish || activeUs >= row.targetMs * 1000) {
        state = FocusState.completed;
        end = sample.utcMs;
      } else {
        state = step == FocusStep.pause
            ? FocusState.paused
            : FocusState.running;
        nextOpen = suspendClock ? null : sample;
      }
    }
    final next = _Envelope(
      start: previous.start,
      open: nextOpen,
      spans: spans,
      step: step.name,
      fromRevision: expectedRevision,
      commandSample: sample,
      suspendClock: suspendClock,
    );
    final changed =
        await (database.update(database.focusSessions)..where(
              (candidate) =>
                  candidate.id.equals(id) &
                  candidate.ownerId.equals(expectedOwnerId) &
                  candidate.revision.equals(expectedRevision) &
                  candidate.state.equals(row.state),
            ))
            .write(
              db.FocusSessionsCompanion(
                state: Value(state.name),
                revision: Value(expectedRevision + 1),
                spansJson: Value(next.encode()),
                endedAtUtcMs: Value(end),
              ),
            );
    if (changed != 1) {
      throw StateError('Focus transition lost its revision');
    }
    return (await load(ownerId: expectedOwnerId, id: id))!;
  });

  Future<FocusWeek> week({
    required String ownerId,
    required DateTime civilMonday,
  }) => database.transaction(() async {
    _identifier(ownerId);
    if (!civilMonday.isUtc ||
        civilMonday.year < 1 ||
        civilMonday.year > 9999 ||
        civilMonday.weekday != DateTime.monday ||
        civilMonday !=
            DateTime.utc(
              civilMonday.year,
              civilMonday.month,
              civilMonday.day,
            )) {
      throw ArgumentError.value(civilMonday, 'civilMonday');
    }
    final label = civilMonday.toIso8601String().substring(0, 10);
    final rows =
        await (database.select(database.focusSessions)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.startedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final snapshots = rows.map((row) => _decode(row).snapshot(row)).toList();
    return FocusWeek(
      civilMonday: civilMonday,
      sessions: snapshots.where((row) => row.startCivilWeek == label),
      unattributed: snapshots.where((row) => row.startCivilWeek == null),
    );
  });

  Future<db.LocalOwner> _owner(String ownerId) async {
    _identifier(ownerId);
    final owner =
        await (database.select(database.localOwners)..where(
              (row) => row.id.equals(ownerId) & row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (owner == null) {
      throw StateError('Focus owner is no longer active');
    }
    return owner;
  }
}

void _identifier(String value) {
  if (value.trim().isEmpty || value.length > 256) {
    throw ArgumentError.value(value, 'identifier');
  }
}

bool _sameSample(FocusSample a, FocusSample b) =>
    a.utcMs == b.utcMs &&
    a.monotonicUs == b.monotonicUs &&
    a.continuityId == b.continuityId;

List<Object> _sampleJson(FocusSample sample) => [
  sample.utcMs,
  sample.monotonicUs,
  sample.continuityId,
];

final class _Envelope {
  _Envelope({
    required this.start,
    required this.open,
    required this.spans,
    required this.step,
    required this.fromRevision,
    required this.commandSample,
    this.suspendClock = false,
  });

  final FocusSample start;
  final FocusSample? open;
  final List<FocusSpan> spans;
  final String step;
  final int fromRevision;
  final FocusSample commandSample;
  final bool suspendClock;

  String encode() {
    if (spans.length > 1000) {
      throw StateError('Focus span limit reached');
    }
    final value = jsonEncode({
      'v': 1,
      'start': _sampleJson(start),
      'open': open == null ? null : _sampleJson(open!),
      'spans': [
        for (final span in spans)
          [
            span.kind.name,
            span.observedStartUtcMs,
            span.observedEndUtcMs,
            span.elapsedUs,
          ],
      ],
      'last': [step, fromRevision, _sampleJson(commandSample), suspendClock],
    });
    if (utf8.encode(value).length > 65536) {
      throw StateError('Focus evidence is too large');
    }
    return value;
  }

  FocusSnapshot snapshot(db.FocusSession row) => FocusSnapshot(
    id: row.id,
    ownerId: row.ownerId,
    originOwnerId: row.originOwnerId,
    targetMs: row.targetMs,
    startedAtUtcMs: row.startedAtUtcMs,
    startRuleId: row.startRuleId,
    startCivilWeek: row.startCivilWeek,
    state: FocusState.values.byName(row.state),
    revision: row.revision,
    spans: spans,
    endedAtUtcMs: row.endedAtUtcMs,
    openSample: row.state == 'running' || row.state == 'paused' ? open : null,
  );
}

_Envelope _decode(db.FocusSession row) {
  try {
    if (utf8.encode(row.spansJson).length > 65536) {
      throw const FormatException('Focus evidence is too large');
    }
    final raw = row.spansJson.trim();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 5 ||
        !decoded.keys.toSet().containsAll([
          'v',
          'start',
          'open',
          'spans',
          'last',
        ]) ||
        decoded['v'] is! int ||
        decoded['v'] != 1 ||
        jsonEncode(decoded) != raw) {
      throw const FormatException('Unsupported focus evidence');
    }
    final start = _parseSample(decoded['start']);
    final open = decoded['open'] == null ? null : _parseSample(decoded['open']);
    final rawSpans = decoded['spans'];
    if (rawSpans is! List || rawSpans.length > 1000) {
      throw const FormatException('Invalid focus spans');
    }
    var boundary = start.utcMs;
    var elapsed = 0;
    final spans = <FocusSpan>[];
    for (final rawSpan in rawSpans) {
      if (rawSpan is! List || rawSpan.length != 4 || rawSpan[0] is! String) {
        throw const FormatException('Invalid focus span');
      }
      final kind = FocusSpanKind.values.byName(rawSpan[0] as String);
      final from = _integer(rawSpan[1], max: 8640000000000000);
      final to = _integer(rawSpan[2], max: 8640000000000000);
      final duration = rawSpan[3] == null ? null : _integer(rawSpan[3]);
      if (from != boundary ||
          (duration == null && kind == FocusSpanKind.active)) {
        throw const FormatException('Invalid focus span continuity');
      }
      elapsed += duration ?? 0;
      if (elapsed > 9007199254740991) {
        throw const FormatException('Focus duration is out of range');
      }
      spans.add(
        FocusSpan(
          kind: kind,
          observedStartUtcMs: from,
          observedEndUtcMs: to,
          elapsedUs: duration,
        ),
      );
      boundary = to;
    }
    final last = decoded['last'];
    if (last is! List ||
        last.length != 4 ||
        last[0] is! String ||
        last[3] is! bool ||
        ![
          'start',
          ...FocusStep.values.map((step) => step.name),
        ].contains(last[0])) {
      throw const FormatException('Invalid focus transition evidence');
    }
    final fromRevision = _integer(last[1]);
    final command = _parseSample(last[2]);
    final state = FocusState.values.byName(row.state);
    final lastStep = last[0] as String;
    final suspended = last[3] as bool;
    _identifier(row.id);
    _identifier(row.ownerId);
    _identifier(row.originOwnerId);
    if (row.targetMs < 1 ||
        row.targetMs > 86400000 ||
        row.revision < 1 ||
        row.startedAtUtcMs != start.utcMs ||
        (row.revision != fromRevision + 1 &&
            !(state == FocusState.interrupted &&
                row.revision == fromRevision + 2)) ||
        row.revision !=
            spans.length + (state == FocusState.interrupted ? 2 : 1) ||
        ((row.startRuleId == null) != (row.startCivilWeek == null))) {
      throw const FormatException('Focus row and evidence disagree');
    }
    if ((suspended && lastStep != 'pause') ||
        (lastStep == 'start' &&
            (fromRevision != 0 ||
                spans.isNotEmpty ||
                !_sameSample(start, command))) ||
        (lastStep != 'start' && fromRevision < 1) ||
        (open != null && !_sameSample(open, command)) ||
        (state == FocusState.running &&
            !['start', 'resume'].contains(lastStep)) ||
        (state == FocusState.paused &&
            (lastStep != 'pause' || (open == null && !suspended))) ||
        (state == FocusState.completed &&
            !['pause', 'finish'].contains(lastStep)) ||
        (state != FocusState.interrupted && command.utcMs != boundary)) {
      throw const FormatException('Invalid focus transition snapshot');
    }
    if (row.startCivilWeek case final label?) {
      final monday = DateTime.tryParse('${label}T00:00:00Z');
      if (label.length != 10 ||
          monday == null ||
          monday.weekday != DateTime.monday ||
          monday.toIso8601String().substring(0, 10) != label) {
        throw const FormatException('Invalid focus week');
      }
    }
    if ((open != null && open.utcMs != boundary) ||
        (state == FocusState.running && open == null) ||
        ((state == FocusState.running || state == FocusState.paused) &&
            row.endedAtUtcMs != null) ||
        (state == FocusState.completed &&
            (open != null || row.endedAtUtcMs != boundary || spans.isEmpty))) {
      throw const FormatException('Invalid focus open boundary');
    }
    return _Envelope(
      start: start,
      open: open,
      spans: spans,
      step: lastStep,
      fromRevision: fromRevision,
      commandSample: command,
      suspendClock: suspended,
    );
  } on ArgumentError {
    throw const FormatException('Invalid focus evidence');
  }
}

int _integer(Object? value, {int max = 9007199254740991}) {
  if (value is! int || value < 0 || value > max) {
    throw const FormatException('Invalid focus integer');
  }
  return value;
}

FocusSample _parseSample(Object? value) {
  if (value is! List || value.length != 3 || value[2] is! String) {
    throw const FormatException('Invalid focus sample');
  }
  final sample = FocusSample(
    utcMs: _integer(value[0], max: 8640000000000000),
    monotonicUs: _integer(value[1]),
    continuityId: value[2] as String,
  );
  sample.validate();
  return sample;
}
