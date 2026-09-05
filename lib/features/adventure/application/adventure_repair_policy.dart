import 'dart:collection';

import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning_packs/domain/content_manifest.dart';

enum AdventureAttemptOutcome {
  correct,
  incorrect,
  skipped,
  technical,
  guided,
  exposure,
}

enum AdventureRepairDisposition {
  scheduled,
  due,
  completed,
  deferredToCanonicalReview,
  alreadyScheduled,
  notApplicable,
}

enum AdventureRepairTicketState { waiting, due, completed, deferred }

typedef AdventureModeEligibility =
    bool Function(
      ContentIdentity identity,
      LessonMode mode,
      String promptVariant,
    );
typedef AdventureRepairSpacing = int Function(ContentIdentity identity);

/// One typed observation made only after the canonical Learning boundary has
/// either committed an answer or explicitly reported a non-evidence outcome.
final class AdventureRepairAttempt {
  AdventureRepairAttempt({
    required this.identity,
    required this.mode,
    required this.promptVariant,
    required this.outcome,
    required this.evidenceClass,
    required this.canonicalEvidenceCommitted,
    required this.sourceEvidenceId,
    this.isRepair = false,
  }) {
    if (identity.id.isEmpty ||
        identity.id != identity.id.trim() ||
        identity.revision <= 0) {
      throw ArgumentError.value(identity, 'identity', 'must be canonical');
    }
    if (promptVariant.isEmpty ||
        promptVariant != promptVariant.trim() ||
        promptVariant.runes.length > 60) {
      throw ArgumentError.value(
        promptVariant,
        'promptVariant',
        'must be canonical',
      );
    }
    if (!isAdventureRepairPromptAuthorized(mode, promptVariant)) {
      throw ArgumentError.value(
        promptVariant,
        'promptVariant',
        'is not authorized for ${mode.name}',
      );
    }
    final evidenceId = sourceEvidenceId;
    if (canonicalEvidenceCommitted !=
        (evidenceId != null && evidenceClass != null)) {
      throw ArgumentError(
        'Committed repair observations require exactly one evidence identity.',
      );
    }
    if (evidenceId != null &&
        (evidenceId.isEmpty ||
            evidenceId != evidenceId.trim() ||
            evidenceId.runes.length > 256)) {
      throw ArgumentError.value(
        evidenceId,
        'sourceEvidenceId',
        'must be canonical',
      );
    }
  }

  final ContentIdentity identity;
  final LessonMode mode;
  final String promptVariant;
  final AdventureAttemptOutcome outcome;
  final EvidenceClass? evidenceClass;
  final bool canonicalEvidenceCommitted;
  final String? sourceEvidenceId;
  final bool isRepair;

  bool get isEligibleInterveningAnswer =>
      !isRepair &&
      canonicalEvidenceCommitted &&
      evidenceClass == EvidenceClass.independentRecall;

  bool get isCommittedIncorrect =>
      !isRepair &&
      canonicalEvidenceCommitted &&
      outcome == AdventureAttemptOutcome.incorrect;
}

final class AdventureRepairTicket {
  AdventureRepairTicket._({
    required this.identity,
    required this.originalMode,
    required this.originalPromptVariant,
    required this.repairMode,
    required this.repairPromptVariant,
    required this.originalEvidenceId,
    required this.dueAfterEligibleItems,
    required this.state,
    required this.ordinal,
    required Set<ContentIdentity> eligibleInterveningIdentities,
  }) : eligibleInterveningIdentities = UnmodifiableSetView<ContentIdentity>(
         eligibleInterveningIdentities,
       );

  final ContentIdentity identity;
  final LessonMode originalMode;
  final String originalPromptVariant;
  final LessonMode? repairMode;
  final String? repairPromptVariant;
  final String originalEvidenceId;
  final int dueAfterEligibleItems;
  final AdventureRepairTicketState state;
  final int ordinal;
  final Set<ContentIdentity> eligibleInterveningIdentities;
}

final class AdventureRepairDecision {
  AdventureRepairDecision({
    required this.disposition,
    Iterable<AdventureRepairTicket> dueRepairs =
        const <AdventureRepairTicket>[],
  }) : dueRepairs = List<AdventureRepairTicket>.unmodifiable(dueRepairs);

  final AdventureRepairDisposition disposition;
  final List<AdventureRepairTicket> dueRepairs;
}

final class AdventureRepairPolicySnapshot {
  AdventureRepairPolicySnapshot._({
    required this.nextOrdinal,
    required Iterable<AdventureRepairTicket> tickets,
  }) : tickets = List<AdventureRepairTicket>.unmodifiable(tickets);

  factory AdventureRepairPolicySnapshot.fromJson(Map<String, Object?> json) {
    const keys = <String>{'schemaVersion', 'nextOrdinal', 'tickets'};
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['schemaVersion'] is! int ||
        json['schemaVersion'] != currentSchemaVersion ||
        json['nextOrdinal'] is! int ||
        json['tickets'] is! List<Object?>) {
      throw const FormatException('invalid Adventure repair snapshot schema');
    }
    final nextOrdinal = json['nextOrdinal']! as int;
    final rawTickets = json['tickets']! as List<Object?>;
    if (nextOrdinal < 0 ||
        rawTickets.length > 100 ||
        nextOrdinal != rawTickets.length) {
      throw const FormatException('invalid Adventure repair snapshot bounds');
    }
    final tickets = <AdventureRepairTicket>[];
    final identities = <ContentIdentity>{};
    final evidenceIds = <String>{};
    final ordinals = <int>{};
    for (final raw in rawTickets) {
      if (raw is! Map) {
        throw const FormatException('invalid Adventure repair ticket');
      }
      late final Map<String, Object?> ticketJson;
      try {
        ticketJson = raw.cast<String, Object?>();
      } on Object {
        throw const FormatException('invalid Adventure repair ticket');
      }
      tickets.add(_decodeTicket(ticketJson));
      final ticket = tickets.last;
      if (!identities.add(ticket.identity) ||
          !evidenceIds.add(ticket.originalEvidenceId) ||
          !ordinals.add(ticket.ordinal)) {
        throw const FormatException('duplicate Adventure repair identity');
      }
    }
    final sortedOrdinals = ordinals.toList()..sort();
    for (var index = 0; index < sortedOrdinals.length; index += 1) {
      if (sortedOrdinals[index] != index) {
        throw const FormatException('invalid Adventure repair ticket order');
      }
    }
    return AdventureRepairPolicySnapshot._(
      nextOrdinal: nextOrdinal,
      tickets: tickets,
    );
  }

  static const int currentSchemaVersion = 1;

  final int nextOrdinal;
  final List<AdventureRepairTicket> tickets;

  Map<String, Object?> toJson() => _freezeJsonMap(<String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'nextOrdinal': nextOrdinal,
    'tickets': <Object?>[
      for (final ticket in tickets)
        <String, Object?>{
          'identity': _identityToJson(ticket.identity),
          'originalMode': ticket.originalMode.name,
          'originalPromptVariant': ticket.originalPromptVariant,
          'repairMode': ticket.repairMode?.name,
          'repairPromptVariant': ticket.repairPromptVariant,
          'originalEvidenceId': ticket.originalEvidenceId,
          'dueAfterEligibleItems': ticket.dueAfterEligibleItems,
          'state': ticket.state.name,
          'ordinal': ticket.ordinal,
          'eligibleInterveningIdentities': <Object?>[
            for (final identity
                in (ticket.eligibleInterveningIdentities.toList()
                  ..sort(_compareIdentity)))
              _identityToJson(identity),
          ],
        },
    ],
  });

  static AdventureRepairTicket _decodeTicket(Map<String, Object?> json) {
    const keys = <String>{
      'identity',
      'originalMode',
      'originalPromptVariant',
      'repairMode',
      'repairPromptVariant',
      'originalEvidenceId',
      'dueAfterEligibleItems',
      'state',
      'ordinal',
      'eligibleInterveningIdentities',
    };
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['originalPromptVariant'] is! String ||
        json['originalEvidenceId'] is! String ||
        json['dueAfterEligibleItems'] is! int ||
        json['ordinal'] is! int ||
        json['eligibleInterveningIdentities'] is! List<Object?>) {
      throw const FormatException('invalid Adventure repair ticket schema');
    }
    final identity = _identityFromJson(json['identity']);
    final originalMode = _enumByName(
      LessonMode.values,
      json['originalMode'],
      'originalMode',
    );
    final originalPromptVariant = json['originalPromptVariant']! as String;
    final repairMode = json['repairMode'] == null
        ? null
        : _enumByName(LessonMode.values, json['repairMode'], 'repairMode');
    final repairPromptVariant = json['repairPromptVariant'];
    if (repairPromptVariant != null && repairPromptVariant is! String) {
      throw const FormatException('invalid Adventure repair prompt variant');
    }
    final state = _enumByName(
      AdventureRepairTicketState.values,
      json['state'],
      'state',
    );
    final originalEvidenceId = json['originalEvidenceId']! as String;
    final dueAfter = json['dueAfterEligibleItems']! as int;
    final ordinal = json['ordinal']! as int;
    final intervening = <ContentIdentity>{};
    for (final raw in json['eligibleInterveningIdentities']! as List<Object?>) {
      final item = _identityFromJson(raw);
      if (item == identity || !intervening.add(item)) {
        throw const FormatException(
          'invalid Adventure repair intervening identity',
        );
      }
    }
    final validEvidenceId =
        originalEvidenceId.isNotEmpty &&
        originalEvidenceId == originalEvidenceId.trim() &&
        originalEvidenceId.runes.length <= 256;
    final validOriginalPrompt = _isCanonicalPrompt(originalPromptVariant);
    final hasScheduledMode = repairMode != null;
    final hasScheduledPrompt = repairPromptVariant is String;
    final validScheduledBounds =
        dueAfter >= AdventureRepairPolicy.minimumInterveningItems &&
        dueAfter <= AdventureRepairPolicy.maximumInterveningItems &&
        intervening.length <= dueAfter;
    final validState = switch (state) {
      AdventureRepairTicketState.waiting =>
        hasScheduledMode &&
            validScheduledBounds &&
            intervening.length < dueAfter,
      AdventureRepairTicketState.due =>
        hasScheduledMode &&
            validScheduledBounds &&
            intervening.length == dueAfter,
      AdventureRepairTicketState.completed =>
        hasScheduledMode &&
            validScheduledBounds &&
            intervening.length == dueAfter,
      AdventureRepairTicketState.deferred =>
        (!hasScheduledMode && dueAfter == 0 && intervening.isEmpty) ||
            (hasScheduledMode && validScheduledBounds),
    };
    final validTransition = _isAuthorizedTransition(
      originalMode: originalMode,
      originalPromptVariant: originalPromptVariant,
      repairMode: repairMode,
      repairPromptVariant: repairPromptVariant as String?,
    );
    if (!validEvidenceId ||
        !validOriginalPrompt ||
        hasScheduledMode != hasScheduledPrompt ||
        ordinal < 0 ||
        !validState ||
        !validTransition) {
      throw const FormatException('invalid Adventure repair ticket values');
    }
    return AdventureRepairTicket._(
      identity: identity,
      originalMode: originalMode,
      originalPromptVariant: originalPromptVariant,
      repairMode: repairMode,
      repairPromptVariant: repairPromptVariant,
      originalEvidenceId: originalEvidenceId,
      dueAfterEligibleItems: dueAfter,
      state: state,
      ordinal: ordinal,
      eligibleInterveningIdentities: intervening,
    );
  }

  static ContentIdentity _identityFromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('invalid Adventure repair content identity');
    }
    late final Map<String, Object?> json;
    try {
      json = raw.cast<String, Object?>();
    } on Object {
      throw const FormatException('invalid Adventure repair content identity');
    }
    const keys = <String>{'type', 'id', 'revision'};
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['type'] != ContentType.lexicalMetadata.name ||
        json['id'] is! String ||
        json['revision'] is! int) {
      throw const FormatException('invalid Adventure repair content identity');
    }
    final id = json['id']! as String;
    final revision = json['revision']! as int;
    if (id.isEmpty || id != id.trim() || revision <= 0) {
      throw const FormatException('invalid Adventure repair content identity');
    }
    return ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: id,
      revision: revision,
    );
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? raw,
    String field,
  ) {
    if (raw is! String) {
      throw FormatException('invalid Adventure repair $field');
    }
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('invalid Adventure repair $field');
  }

  static int _compareIdentity(ContentIdentity left, ContentIdentity right) {
    final type = left.type.name.compareTo(right.type.name);
    if (type != 0) return type;
    final id = left.id.compareTo(right.id);
    if (id != 0) return id;
    return left.revision.compareTo(right.revision);
  }

  static bool _isCanonicalPrompt(String value) =>
      value.isNotEmpty && value == value.trim() && value.runes.length <= 60;

  static bool _isAuthorizedTransition({
    required LessonMode originalMode,
    required String originalPromptVariant,
    required LessonMode? repairMode,
    required String? repairPromptVariant,
  }) {
    if (!_repairModes.contains(originalMode)) return false;
    if (!isAdventureRepairPromptAuthorized(
      originalMode,
      originalPromptVariant,
    )) {
      return false;
    }
    if (repairMode == null) {
      return repairPromptVariant == null;
    }
    final expectedPrompt = _promptForRepairMode(repairMode);
    if (repairPromptVariant != expectedPrompt) return false;
    return _supportiveTargetsFor(originalMode).contains(repairMode);
  }

  static const Set<LessonMode> _repairModes = <LessonMode>{
    LessonMode.typedRecall,
    LessonMode.cloze,
    LessonMode.meaningQuiz,
    LessonMode.definitionQuiz,
    LessonMode.matching,
    LessonMode.flashcard,
  };
}

/// Bounded in-session plan decoration. It never writes evidence, Review/SRS,
/// progress, or reward state. The original incorrect Learning evidence is the
/// sole durable Review authority; a deferral here therefore creates no second
/// Adventure event and a later successful support item cannot erase history.
final class AdventureRepairPolicy {
  AdventureRepairPolicy({
    required this.isModeEligible,
    AdventureRepairSpacing? spacingForIdentity,
  }) : _spacingForIdentity = spacingForIdentity ?? _stableSpacing;

  factory AdventureRepairPolicy.restore(
    AdventureRepairPolicySnapshot snapshot, {
    required AdventureModeEligibility isModeEligible,
    AdventureRepairSpacing? spacingForIdentity,
  }) {
    final policy = AdventureRepairPolicy(
      isModeEligible: isModeEligible,
      spacingForIdentity: spacingForIdentity,
    );
    for (final ticket in snapshot.tickets) {
      policy._tickets[ticket.identity] =
          _MutableRepairTicket(
              identity: ticket.identity,
              originalMode: ticket.originalMode,
              originalPromptVariant: ticket.originalPromptVariant,
              repairMode: ticket.repairMode,
              repairPromptVariant: ticket.repairPromptVariant,
              originalEvidenceId: ticket.originalEvidenceId,
              dueAfterEligibleItems: ticket.dueAfterEligibleItems,
              state: ticket.state,
              ordinal: ticket.ordinal,
            )
            ..eligibleInterveningIdentities.addAll(
              ticket.eligibleInterveningIdentities,
            );
      policy._originalEvidenceIdentities[ticket.originalEvidenceId] =
          ticket.identity;
    }
    policy._nextOrdinal = snapshot.nextOrdinal;
    return policy;
  }

  static const int minimumInterveningItems = 3;
  static const int maximumInterveningItems = 5;

  final AdventureModeEligibility isModeEligible;
  final AdventureRepairSpacing _spacingForIdentity;
  final Map<ContentIdentity, _MutableRepairTicket> _tickets =
      <ContentIdentity, _MutableRepairTicket>{};
  final Map<String, ContentIdentity> _originalEvidenceIdentities =
      <String, ContentIdentity>{};
  var _nextOrdinal = 0;

  List<AdventureRepairTicket> get tickets =>
      List<AdventureRepairTicket>.unmodifiable(
        _orderedTickets().map((ticket) => ticket.snapshot()),
      );

  List<AdventureRepairTicket> get dueRepairs =>
      List<AdventureRepairTicket>.unmodifiable(
        _orderedTickets()
            .where((ticket) => ticket.state == AdventureRepairTicketState.due)
            .map((ticket) => ticket.snapshot()),
      );

  AdventureRepairPolicySnapshot snapshot() => AdventureRepairPolicySnapshot._(
    nextOrdinal: _nextOrdinal,
    tickets: tickets,
  );

  AdventureRepairDecision recordAttempt({
    required AdventureRepairAttempt attempt,
    required int remainingOriginalItems,
  }) {
    if (remainingOriginalItems < 0) {
      throw ArgumentError.value(
        remainingOriginalItems,
        'remainingOriginalItems',
        'must not be negative',
      );
    }
    if (attempt.isRepair) {
      return _recordRepair(attempt);
    }

    final newlyDue = attempt.isEligibleInterveningAnswer
        ? _observeEligibleIntervening(attempt.identity)
        : const <AdventureRepairTicket>[];
    var disposition = AdventureRepairDisposition.notApplicable;
    if (attempt.isCommittedIncorrect) {
      disposition = _schedule(
        attempt: attempt,
        remainingOriginalItems: remainingOriginalItems,
      );
    }
    return AdventureRepairDecision(
      disposition: disposition,
      dueRepairs: newlyDue,
    );
  }

  List<AdventureRepairTicket> deferRemaining() {
    final deferred = <AdventureRepairTicket>[];
    for (final ticket in _orderedTickets()) {
      if (ticket.state == AdventureRepairTicketState.waiting ||
          ticket.state == AdventureRepairTicketState.due) {
        ticket.state = AdventureRepairTicketState.deferred;
        deferred.add(ticket.snapshot());
      }
    }
    return List<AdventureRepairTicket>.unmodifiable(deferred);
  }

  AdventureRepairDisposition _schedule({
    required AdventureRepairAttempt attempt,
    required int remainingOriginalItems,
  }) {
    final evidenceId = attempt.sourceEvidenceId!;
    final evidenceIdentity = _originalEvidenceIdentities[evidenceId];
    if (evidenceIdentity != null && evidenceIdentity != attempt.identity) {
      throw StateError(
        'An incorrect evidence identity was reused for another content item.',
      );
    }
    final existing = _tickets[attempt.identity];
    if (existing != null) {
      if (existing.originalEvidenceId != evidenceId) {
        throw StateError(
          'A content identity was reused with another incorrect evidence ID.',
        );
      }
      return AdventureRepairDisposition.alreadyScheduled;
    }

    final repairTarget = _nextSupportiveTarget(
      identity: attempt.identity,
      current: attempt.mode,
    );
    final canSchedule =
        attempt.evidenceClass == EvidenceClass.independentRecall &&
        repairTarget != null &&
        remainingOriginalItems >= minimumInterveningItems;
    final desiredSpacing = _spacingForIdentity(attempt.identity);
    if (desiredSpacing < minimumInterveningItems ||
        desiredSpacing > maximumInterveningItems) {
      throw StateError('Repair spacing must remain between 3 and 5.');
    }
    final dueAfter = canSchedule
        ? desiredSpacing.clamp(
            minimumInterveningItems,
            remainingOriginalItems < maximumInterveningItems
                ? remainingOriginalItems
                : maximumInterveningItems,
          )
        : 0;
    _originalEvidenceIdentities[evidenceId] = attempt.identity;
    _tickets[attempt.identity] = _MutableRepairTicket(
      identity: attempt.identity,
      originalMode: attempt.mode,
      originalPromptVariant: attempt.promptVariant,
      repairMode: canSchedule ? repairTarget.mode : null,
      repairPromptVariant: canSchedule ? repairTarget.promptVariant : null,
      originalEvidenceId: evidenceId,
      dueAfterEligibleItems: dueAfter,
      state: canSchedule
          ? AdventureRepairTicketState.waiting
          : AdventureRepairTicketState.deferred,
      ordinal: _nextOrdinal,
    );
    _nextOrdinal += 1;
    return canSchedule
        ? AdventureRepairDisposition.scheduled
        : AdventureRepairDisposition.deferredToCanonicalReview;
  }

  List<AdventureRepairTicket> _observeEligibleIntervening(
    ContentIdentity identity,
  ) {
    final due = <AdventureRepairTicket>[];
    for (final ticket in _orderedTickets()) {
      if (ticket.state != AdventureRepairTicketState.waiting ||
          ticket.identity == identity ||
          !ticket.eligibleInterveningIdentities.add(identity)) {
        continue;
      }
      if (ticket.eligibleInterveningIdentities.length ==
          ticket.dueAfterEligibleItems) {
        ticket.state = AdventureRepairTicketState.due;
        due.add(ticket.snapshot());
      }
    }
    return List<AdventureRepairTicket>.unmodifiable(due);
  }

  AdventureRepairDecision _recordRepair(AdventureRepairAttempt attempt) {
    final ticket = _tickets[attempt.identity];
    if (ticket == null) {
      return AdventureRepairDecision(
        disposition: AdventureRepairDisposition.notApplicable,
      );
    }
    if (ticket.state == AdventureRepairTicketState.completed ||
        ticket.state == AdventureRepairTicketState.deferred) {
      return AdventureRepairDecision(
        disposition: AdventureRepairDisposition.alreadyScheduled,
      );
    }
    if (ticket.state != AdventureRepairTicketState.due) {
      throw StateError('Repair cannot run before its eligible spacing is met.');
    }
    if (ticket.repairMode != attempt.mode ||
        ticket.repairPromptVariant != attempt.promptVariant) {
      throw StateError(
        'Repair mode or prompt does not match the scheduled support.',
      );
    }
    if (attempt.outcome == AdventureAttemptOutcome.technical) {
      return AdventureRepairDecision(
        disposition: AdventureRepairDisposition.notApplicable,
      );
    }
    final checkpointOnlyExposure =
        ticket.repairMode == LessonMode.flashcard &&
        attempt.outcome == AdventureAttemptOutcome.exposure &&
        !attempt.canonicalEvidenceCommitted;
    if (!attempt.canonicalEvidenceCommitted &&
        attempt.outcome != AdventureAttemptOutcome.skipped &&
        !checkpointOnlyExposure) {
      return AdventureRepairDecision(
        disposition: AdventureRepairDisposition.notApplicable,
      );
    }

    final failed =
        attempt.outcome == AdventureAttemptOutcome.incorrect ||
        attempt.outcome == AdventureAttemptOutcome.skipped;
    if (failed) {
      ticket.state = AdventureRepairTicketState.deferred;
      return AdventureRepairDecision(
        disposition: AdventureRepairDisposition.deferredToCanonicalReview,
      );
    }
    ticket.state = AdventureRepairTicketState.completed;
    return AdventureRepairDecision(
      disposition: AdventureRepairDisposition.completed,
    );
  }

  List<_MutableRepairTicket> _orderedTickets() =>
      _tickets.values.toList()
        ..sort((left, right) => left.ordinal.compareTo(right.ordinal));

  _RepairTarget? _nextSupportiveTarget({
    required ContentIdentity identity,
    required LessonMode current,
  }) {
    final candidates = _supportiveTargetsFor(current);
    for (final mode in candidates) {
      final promptVariant = _promptForRepairMode(mode);
      if (isModeEligible(identity, mode, promptVariant)) {
        return _RepairTarget(mode, promptVariant);
      }
    }
    return null;
  }

  static int _stableSpacing(ContentIdentity identity) {
    final value = '${identity.type.name}:${identity.id}:${identity.revision}';
    final seed = value.codeUnits.fold<int>(
      17,
      (hash, unit) => ((hash * 31) + unit) & 0x7fffffff,
    );
    return minimumInterveningItems +
        (seed % (maximumInterveningItems - minimumInterveningItems + 1));
  }
}

final class _MutableRepairTicket {
  _MutableRepairTicket({
    required this.identity,
    required this.originalMode,
    required this.originalPromptVariant,
    required this.repairMode,
    required this.repairPromptVariant,
    required this.originalEvidenceId,
    required this.dueAfterEligibleItems,
    required this.state,
    required this.ordinal,
  });

  final ContentIdentity identity;
  final LessonMode originalMode;
  final String originalPromptVariant;
  final LessonMode? repairMode;
  final String? repairPromptVariant;
  final String originalEvidenceId;
  final int dueAfterEligibleItems;
  AdventureRepairTicketState state;
  final int ordinal;
  final Set<ContentIdentity> eligibleInterveningIdentities =
      <ContentIdentity>{};

  AdventureRepairTicket snapshot() => AdventureRepairTicket._(
    identity: identity,
    originalMode: originalMode,
    originalPromptVariant: originalPromptVariant,
    repairMode: repairMode,
    repairPromptVariant: repairPromptVariant,
    originalEvidenceId: originalEvidenceId,
    dueAfterEligibleItems: dueAfterEligibleItems,
    state: state,
    ordinal: ordinal,
    eligibleInterveningIdentities: Set<ContentIdentity>.of(
      eligibleInterveningIdentities,
    ),
  );
}

final class _RepairTarget {
  const _RepairTarget(this.mode, this.promptVariant);

  final LessonMode mode;
  final String promptVariant;
}

List<LessonMode> _supportiveTargetsFor(LessonMode mode) => switch (mode) {
  LessonMode.typedRecall => const <LessonMode>[
    LessonMode.cloze,
    LessonMode.meaningQuiz,
    LessonMode.definitionQuiz,
    LessonMode.matching,
    LessonMode.flashcard,
  ],
  LessonMode.cloze => const <LessonMode>[
    LessonMode.meaningQuiz,
    LessonMode.definitionQuiz,
    LessonMode.matching,
    LessonMode.flashcard,
  ],
  LessonMode.meaningQuiz ||
  LessonMode.definitionQuiz ||
  LessonMode.matching => const <LessonMode>[LessonMode.flashcard],
  LessonMode.flashcard => const <LessonMode>[],
  _ => const <LessonMode>[],
};

String _promptForRepairMode(LessonMode mode) => switch (mode) {
  LessonMode.cloze => 'clozeSelected',
  LessonMode.meaningQuiz => 'meaningChoice',
  LessonMode.definitionQuiz => 'definitionChoice',
  LessonMode.matching => 'matchingPair',
  LessonMode.flashcard => 'flashcardExposure',
  _ => throw StateError('${mode.name} is not a repair target.'),
};

bool isAdventureRepairPromptAuthorized(LessonMode mode, String promptVariant) =>
    switch (mode) {
      LessonMode.typedRecall =>
        promptVariant == 'typedRecall' || promptVariant == 'associativeRecall',
      LessonMode.cloze =>
        promptVariant == 'clozeSelected' || promptVariant == 'clozeTyped',
      LessonMode.meaningQuiz =>
        promptVariant == 'meaningChoice' || promptVariant == 'wordChoice',
      LessonMode.definitionQuiz => promptVariant == 'definitionChoice',
      LessonMode.matching => promptVariant == 'matchingPair',
      LessonMode.flashcard =>
        promptVariant == 'flashcardExposure' || promptVariant == 'srsRecall',
      _ => false,
    };

Map<String, Object?> _identityToJson(ContentIdentity identity) =>
    <String, Object?>{
      'type': identity.type.name,
      'id': identity.id,
      'revision': identity.revision,
    };

Map<String, Object?> _freezeJsonMap(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final entry in source.entries)
        entry.key: _freezeJsonValue(entry.value),
    });

Object? _freezeJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map<String, Object?>) return _freezeJsonMap(value);
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  throw ArgumentError.value(value, 'value', 'must be JSON data');
}
