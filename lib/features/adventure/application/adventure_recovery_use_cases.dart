import 'dart:collection';
import 'dart:convert';

import '../../learning/application/current_activity_evidence.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/adventure_session_plan.dart';
import 'adventure_mixed_review_prompt_catalog.dart';
import 'adventure_repair_policy.dart';

const String mixedReviewActivityType = 'mixedReview';

enum AdventureLearningPresentation { adventure, standard }

enum AdventureLearningCheckpointPhase {
  active,
  pendingOccurrence,
  closing,
  completed,
}

enum AdventureLearningItemRole { original, repair }

typedef AdventurePromptCatalogSnapshotBuilder =
    Future<AdventureMixedReviewCatalogSnapshot> Function(QuizSession session);

final class AdventureLearningPendingOccurrence {
  factory AdventureLearningPendingOccurrence.fromJson(
    Map<String, Object?> json,
  ) {
    const legacyKeys = <String>{
      'identity',
      'role',
      'lessonMode',
      'promptVariant',
      'ordinal',
      'evidence',
    };
    const keys = <String>{...legacyKeys, 'checkpointOnlyOutcome'};
    final isLegacy =
        json.length == legacyKeys.length &&
        json.keys.every(legacyKeys.contains);
    final isCurrent =
        json.length == keys.length && json.keys.every(keys.contains);
    if ((!isLegacy && !isCurrent) || json['ordinal'] is! int) {
      throw const FormatException(
        'invalid mixed-review pending occurrence schema',
      );
    }
    final evidenceJson = json['evidence'];
    final role = AdventureLearningCheckpointState._enumByName(
      AdventureLearningItemRole.values,
      json['role'],
      'pendingOccurrence.role',
    );
    final mode = AdventureLearningCheckpointState._enumByName(
      LessonMode.values,
      json['lessonMode'],
      'pendingOccurrence.lessonMode',
    );
    final promptVariant = AdventureLearningCheckpointState._requiredString(
      json,
      'promptVariant',
    );
    final checkpointOnlyOutcome = isCurrent
        ? _decodeCheckpointOnlyOutcome(json['checkpointOnlyOutcome'])
        : _inferLegacyCheckpointOnlyOutcome(
            role: role,
            mode: mode,
            promptVariant: promptVariant,
            hasEvidence: evidenceJson != null,
          );
    return AdventureLearningPendingOccurrence._validated(
      identity: _decodeLearningIdentity(json['identity']),
      role: role,
      mode: mode,
      promptVariant: promptVariant,
      ordinal: json['ordinal']! as int,
      evidence: evidenceJson == null
          ? null
          : FrozenPendingCurrentActivityEvidence.fromJson(
              AdventureLearningCheckpointState._requiredMap(
                evidenceJson,
                'pendingOccurrence.evidence',
              ),
            ),
      checkpointOnlyOutcome: checkpointOnlyOutcome,
    );
  }

  static AdventureAttemptOutcome? _decodeCheckpointOnlyOutcome(Object? raw) =>
      raw == null
      ? null
      : AdventureLearningCheckpointState._enumByName(
          AdventureAttemptOutcome.values,
          raw,
          'pendingOccurrence.checkpointOnlyOutcome',
        );

  static AdventureAttemptOutcome? _inferLegacyCheckpointOnlyOutcome({
    required AdventureLearningItemRole role,
    required LessonMode mode,
    required String promptVariant,
    required bool hasEvidence,
  }) {
    if (hasEvidence) return null;
    if (role == AdventureLearningItemRole.repair &&
        mode == LessonMode.flashcard &&
        promptVariant == 'flashcardExposure') {
      throw const FormatException(
        'legacy flashcard checkpoint has ambiguous completion intent',
      );
    }
    return AdventureAttemptOutcome.skipped;
  }

  factory AdventureLearningPendingOccurrence._validated({
    required ContentIdentity identity,
    required AdventureLearningItemRole role,
    required LessonMode mode,
    required String promptVariant,
    required int ordinal,
    required FrozenPendingCurrentActivityEvidence? evidence,
    required AdventureAttemptOutcome? checkpointOnlyOutcome,
  }) {
    if (identity.type != ContentType.lexicalMetadata ||
        identity.id.isEmpty ||
        identity.id != identity.id.trim() ||
        identity.revision <= 0 ||
        !isAdventureRepairPromptAuthorized(mode, promptVariant) ||
        ordinal < 1 ||
        ordinal > AdventureRecoveryUseCases.maximumOccurrences) {
      throw const FormatException('invalid mixed-review pending occurrence');
    }
    if (evidence != null &&
        (evidence.wordId != identity.id ||
            evidence.promptMode != promptVariant ||
            evidence.attemptNumber != ordinal)) {
      throw const FormatException(
        'pending evidence conflicts with its mixed-review occurrence',
      );
    }
    final validCheckpointOnlyOutcome = evidence != null
        ? checkpointOnlyOutcome == null
        : checkpointOnlyOutcome == AdventureAttemptOutcome.skipped ||
              checkpointOnlyOutcome == AdventureAttemptOutcome.exposure &&
                  role == AdventureLearningItemRole.repair &&
                  mode == LessonMode.flashcard &&
                  promptVariant == 'flashcardExposure';
    if (!validCheckpointOnlyOutcome) {
      throw const FormatException(
        'invalid mixed-review checkpoint-only completion intent',
      );
    }
    return AdventureLearningPendingOccurrence._(
      identity: identity,
      role: role,
      mode: mode,
      promptVariant: promptVariant,
      ordinal: ordinal,
      evidence: evidence,
      checkpointOnlyOutcome: checkpointOnlyOutcome,
    );
  }

  const AdventureLearningPendingOccurrence._({
    required this.identity,
    required this.role,
    required this.mode,
    required this.promptVariant,
    required this.ordinal,
    required this.evidence,
    required this.checkpointOnlyOutcome,
  });

  final ContentIdentity identity;
  final AdventureLearningItemRole role;
  final LessonMode mode;
  final String promptVariant;
  final int ordinal;
  final FrozenPendingCurrentActivityEvidence? evidence;
  final AdventureAttemptOutcome? checkpointOnlyOutcome;

  Map<String, Object?> toJson() => _freezeJsonMap(<String, Object?>{
    'identity': _encodeLearningIdentity(identity),
    'role': role.name,
    'lessonMode': mode.name,
    'promptVariant': promptVariant,
    'ordinal': ordinal,
    'evidence': evidence?.toJson(),
    'checkpointOnlyOutcome': checkpointOnlyOutcome?.name,
  });
}

/// Minimal Learning-owned reconstruction state. Adventure presentation and
/// plan/catalog provenance stay outside the durable checkpoint; schema v2
/// retains only bounded prompt artifacts required for exact reconstruction.
final class AdventureLearningCheckpointState {
  factory AdventureLearningCheckpointState.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final jsonKeys = switch (schemaVersion) {
      1 => _jsonKeysV1,
      currentSchemaVersion => _jsonKeysV2,
      _ => const <String>{},
    };
    if (jsonKeys.isEmpty ||
        json.length != jsonKeys.length ||
        !json.keys.every(jsonKeys.contains) ||
        json['content'] is! List<Object?> ||
        json['currentOriginalIndex'] is! int ||
        json['nextOccurrenceOrdinal'] is! int ||
        json['summaryPresented'] is! bool) {
      throw const FormatException(
        'invalid Adventure Learning checkpoint schema',
      );
    }
    try {
      final content = <ContentIdentity>[];
      final checksums = <String, String>{};
      for (final raw in json['content']! as List<Object?>) {
        final item = _requiredMap(raw, 'content');
        const keys = <String>{'type', 'id', 'revision', 'checksumSha256'};
        if (item.length != keys.length ||
            !item.keys.every(keys.contains) ||
            item['type'] != ContentType.lexicalMetadata.name ||
            item['id'] is! String ||
            item['revision'] is! int ||
            item['checksumSha256'] is! String) {
          throw const FormatException(
            'invalid Adventure Learning checkpoint content',
          );
        }
        final identity = ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: item['id']! as String,
          revision: item['revision']! as int,
        );
        content.add(identity);
        checksums[identity.id] = item['checksumSha256']! as String;
      }
      final pendingJson = json['pendingOccurrence'];
      final pending = pendingJson == null
          ? null
          : AdventureLearningPendingOccurrence.fromJson(
              _requiredMap(pendingJson, 'pendingOccurrence'),
            );
      final terminalAtUtc = _optionalUtc(
        json['terminalAtUtc'],
        'terminalAtUtc',
      );
      final promptCatalogSnapshot = schemaVersion == currentSchemaVersion
          ? AdventureMixedReviewCatalogSnapshot.fromJson(
              _requiredMap(json['promptCatalog'], 'promptCatalog'),
            )
          : null;
      return AdventureLearningCheckpointState._validated(
        schemaVersion: schemaVersion! as int,
        sessionId: _requiredString(json, 'sessionId'),
        ownerId: _requiredString(json, 'ownerId'),
        mode: _enumByName(LessonMode.values, json['lessonMode'], 'lessonMode'),
        content: content,
        contentChecksumsSha256: checksums,
        currentOriginalIndex: json['currentOriginalIndex']! as int,
        nextOccurrenceOrdinal: json['nextOccurrenceOrdinal']! as int,
        phase: _enumByName(
          AdventureLearningCheckpointPhase.values,
          json['phase'],
          'phase',
        ),
        pendingOccurrence: pending,
        terminalAtUtc: terminalAtUtc,
        summaryPresented: json['summaryPresented']! as bool,
        promptCatalogSnapshot: promptCatalogSnapshot,
        repairPolicySnapshot: AdventureRepairPolicySnapshot.fromJson(
          _requiredMap(json['repairPolicy'], 'repairPolicy'),
        ),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid Adventure Learning checkpoint: $error');
    }
  }

  factory AdventureLearningCheckpointState._validated({
    required int schemaVersion,
    required String sessionId,
    required String ownerId,
    required LessonMode mode,
    required Iterable<ContentIdentity> content,
    required Map<String, String> contentChecksumsSha256,
    required int currentOriginalIndex,
    required int nextOccurrenceOrdinal,
    required AdventureLearningCheckpointPhase phase,
    required AdventureLearningPendingOccurrence? pendingOccurrence,
    required DateTime? terminalAtUtc,
    required bool summaryPresented,
    required AdventureMixedReviewCatalogSnapshot? promptCatalogSnapshot,
    required AdventureRepairPolicySnapshot repairPolicySnapshot,
  }) {
    _requireCanonical(sessionId, 'sessionId');
    _requireCanonical(ownerId, 'ownerId');
    final frozenContent = List<ContentIdentity>.unmodifiable(content);
    if (frozenContent.isEmpty ||
        frozenContent.length > AdventureRecoveryUseCases.maximumOriginalItems) {
      throw const FormatException('mixed-review content exceeds its budget');
    }
    final ids = <String>{};
    for (final identity in frozenContent) {
      _requireCanonical(identity.id, 'content.id');
      final checksum = contentChecksumsSha256[identity.id];
      if (identity.type != ContentType.lexicalMetadata ||
          identity.revision <= 0 ||
          !ids.add(identity.id) ||
          checksum == null ||
          !_sha256.hasMatch(checksum)) {
        throw const FormatException(
          'invalid Adventure Learning content identity',
        );
      }
    }
    if (contentChecksumsSha256.length != ids.length ||
        !contentChecksumsSha256.keys.every(ids.contains) ||
        currentOriginalIndex < 0 ||
        currentOriginalIndex > frozenContent.length ||
        nextOccurrenceOrdinal < 1 ||
        nextOccurrenceOrdinal >
            AdventureRecoveryUseCases.maximumOccurrences + 1) {
      throw const FormatException('invalid Adventure Learning progress');
    }
    if (schemaVersion != 1 && schemaVersion != currentSchemaVersion ||
        schemaVersion == 1 && promptCatalogSnapshot != null ||
        schemaVersion == currentSchemaVersion &&
            promptCatalogSnapshot == null) {
      throw const FormatException(
        'invalid Adventure Learning prompt catalog version',
      );
    }
    final hasPending = pendingOccurrence != null;
    final hasNoPending = pendingOccurrence == null;
    final validPhase = switch (phase) {
      AdventureLearningCheckpointPhase.active =>
        hasNoPending && terminalAtUtc == null && !summaryPresented,
      AdventureLearningCheckpointPhase.pendingOccurrence =>
        hasPending && terminalAtUtc == null && !summaryPresented,
      AdventureLearningCheckpointPhase.closing =>
        hasNoPending && terminalAtUtc != null && !summaryPresented,
      AdventureLearningCheckpointPhase.completed =>
        hasNoPending && terminalAtUtc != null,
    };
    if (!validPhase) {
      throw const FormatException(
        'inconsistent Adventure Learning checkpoint phase',
      );
    }
    if (terminalAtUtc != null &&
        (!terminalAtUtc.isUtc || terminalAtUtc.millisecondsSinceEpoch < 0)) {
      throw const FormatException('invalid Adventure Learning terminal time');
    }
    if (pendingOccurrence != null) {
      final pendingEvidence = pendingOccurrence.evidence;
      final pendingIdentityIndex = frozenContent.indexWhere(
        (identity) => identity == pendingOccurrence.identity,
      );
      final pendingTicket = repairPolicySnapshot.tickets
          .where((ticket) => ticket.identity == pendingOccurrence.identity)
          .toList(growable: false);
      final validOriginal =
          pendingOccurrence.role == AdventureLearningItemRole.original &&
          pendingOccurrence.mode == mode &&
          currentOriginalIndex < frozenContent.length &&
          pendingIdentityIndex == currentOriginalIndex;
      final validRepair =
          pendingOccurrence.role == AdventureLearningItemRole.repair &&
          pendingTicket.length == 1 &&
          pendingTicket.single.state == AdventureRepairTicketState.due &&
          pendingTicket.single.repairMode == pendingOccurrence.mode &&
          pendingTicket.single.repairPromptVariant ==
              pendingOccurrence.promptVariant;
      if (pendingOccurrence.ordinal != nextOccurrenceOrdinal ||
          pendingIdentityIndex < 0 ||
          (!validOriginal && !validRepair) ||
          pendingEvidence != null &&
              (pendingEvidence.ownerId != ownerId ||
                  pendingEvidence.sessionId != sessionId)) {
        throw const FormatException(
          'pending evidence conflicts with Adventure Learning state',
        );
      }
    }
    final contentIdentities = frozenContent.toSet();
    if (repairPolicySnapshot.tickets.any(
      (ticket) => !contentIdentities.contains(ticket.identity),
    )) {
      throw const FormatException(
        'repair ledger contains unpinned Adventure content',
      );
    }
    return AdventureLearningCheckpointState._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      ownerId: ownerId,
      mode: mode,
      content: frozenContent,
      contentChecksumsSha256: UnmodifiableMapView<String, String>(
        Map<String, String>.of(contentChecksumsSha256),
      ),
      currentOriginalIndex: currentOriginalIndex,
      nextOccurrenceOrdinal: nextOccurrenceOrdinal,
      phase: phase,
      pendingOccurrence: pendingOccurrence,
      terminalAtUtc: terminalAtUtc,
      summaryPresented: summaryPresented,
      promptCatalogSnapshot: promptCatalogSnapshot,
      repairPolicySnapshot: repairPolicySnapshot,
    );
  }

  const AdventureLearningCheckpointState._({
    required this.schemaVersion,
    required this.sessionId,
    required this.ownerId,
    required this.mode,
    required this.content,
    required this.contentChecksumsSha256,
    required this.currentOriginalIndex,
    required this.nextOccurrenceOrdinal,
    required this.phase,
    required this.pendingOccurrence,
    required this.terminalAtUtc,
    required this.summaryPresented,
    required this.promptCatalogSnapshot,
    required this.repairPolicySnapshot,
  });

  static const int currentSchemaVersion = 2;
  static const Set<String> _jsonKeysV1 = <String>{
    'schemaVersion',
    'sessionId',
    'ownerId',
    'lessonMode',
    'content',
    'currentOriginalIndex',
    'nextOccurrenceOrdinal',
    'phase',
    'pendingOccurrence',
    'terminalAtUtc',
    'summaryPresented',
    'repairPolicy',
  };
  static const Set<String> _jsonKeysV2 = <String>{
    ..._jsonKeysV1,
    'promptCatalog',
  };
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  final int schemaVersion;
  final String sessionId;
  final String ownerId;
  final LessonMode mode;
  final List<ContentIdentity> content;
  final Map<String, String> contentChecksumsSha256;
  final int currentOriginalIndex;
  final int nextOccurrenceOrdinal;
  final AdventureLearningCheckpointPhase phase;
  final AdventureLearningPendingOccurrence? pendingOccurrence;
  final DateTime? terminalAtUtc;
  final bool summaryPresented;
  final AdventureMixedReviewCatalogSnapshot? promptCatalogSnapshot;
  final AdventureRepairPolicySnapshot repairPolicySnapshot;

  Map<String, Object?> toJson() => _freezeJsonMap(<String, Object?>{
    'schemaVersion': schemaVersion,
    'sessionId': sessionId,
    'ownerId': ownerId,
    'lessonMode': mode.name,
    'content': <Object?>[
      for (final identity in content)
        <String, Object?>{
          'type': identity.type.name,
          'id': identity.id,
          'revision': identity.revision,
          'checksumSha256': contentChecksumsSha256[identity.id],
        },
    ],
    'currentOriginalIndex': currentOriginalIndex,
    'nextOccurrenceOrdinal': nextOccurrenceOrdinal,
    'phase': phase.name,
    'pendingOccurrence': pendingOccurrence?.toJson(),
    'terminalAtUtc': terminalAtUtc?.toIso8601String(),
    'summaryPresented': summaryPresented,
    if (schemaVersion == currentSchemaVersion)
      'promptCatalog': promptCatalogSnapshot!.toJson(),
    'repairPolicy': repairPolicySnapshot.toJson(),
  });

  AdventureLearningCheckpointState transition({
    required int currentOriginalIndex,
    int? nextOccurrenceOrdinal,
    required AdventureLearningCheckpointPhase phase,
    required AdventureRepairPolicySnapshot repairPolicySnapshot,
    AdventureLearningPendingOccurrence? pendingOccurrence,
    DateTime? terminalAtUtc,
    bool? summaryPresented,
  }) => AdventureLearningCheckpointState._validated(
    schemaVersion: schemaVersion,
    sessionId: sessionId,
    ownerId: ownerId,
    mode: mode,
    content: content,
    contentChecksumsSha256: contentChecksumsSha256,
    currentOriginalIndex: currentOriginalIndex,
    nextOccurrenceOrdinal: nextOccurrenceOrdinal ?? this.nextOccurrenceOrdinal,
    phase: phase,
    pendingOccurrence: pendingOccurrence,
    terminalAtUtc: terminalAtUtc,
    summaryPresented: summaryPresented ?? this.summaryPresented,
    promptCatalogSnapshot: promptCatalogSnapshot,
    repairPolicySnapshot: repairPolicySnapshot,
  );

  static Map<String, Object?> _requiredMap(Object? raw, String field) {
    if (raw is! Map) {
      throw FormatException('invalid Adventure Learning $field');
    }
    try {
      return raw.cast<String, Object?>();
    } on Object {
      throw FormatException('invalid Adventure Learning $field');
    }
  }

  static String _requiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw FormatException('invalid Adventure Learning $field');
    }
    return value;
  }

  static DateTime? _optionalUtc(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is! String || !raw.endsWith('Z')) {
      throw FormatException('invalid Adventure Learning $field');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.toIso8601String() != raw ||
        parsed.millisecondsSinceEpoch < 0) {
      throw FormatException('invalid Adventure Learning $field');
    }
    return parsed;
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? raw,
    String field,
  ) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    throw FormatException('invalid Adventure Learning $field');
  }

  static void _requireCanonical(String value, String field) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw FormatException('invalid Adventure Learning $field');
    }
  }
}

final class AdventureLearningRun {
  const AdventureLearningRun._({
    required this.session,
    required this.state,
    required this.pendingEvidence,
    required this.pendingClose,
    required this.repairPolicy,
    required this.checkpointRevision,
    required this.recovered,
    required this.presentation,
  });

  final QuizSession session;
  final AdventureLearningCheckpointState state;
  final PendingCurrentActivityEvidence? pendingEvidence;
  final PendingLearningSessionClose? pendingClose;
  final AdventureRepairPolicy repairPolicy;
  final int checkpointRevision;
  final bool recovered;
  final AdventureLearningPresentation presentation;

  AdventureLearningRun _copyWith({
    AdventureLearningCheckpointState? state,
    PendingCurrentActivityEvidence? pendingEvidence,
    bool clearPendingEvidence = false,
    PendingLearningSessionClose? pendingClose,
    bool clearPendingClose = false,
    int? checkpointRevision,
    AdventureLearningPresentation? presentation,
  }) => AdventureLearningRun._(
    session: session,
    state: state ?? this.state,
    pendingEvidence: clearPendingEvidence
        ? null
        : pendingEvidence ?? this.pendingEvidence,
    pendingClose: clearPendingClose ? null : pendingClose ?? this.pendingClose,
    repairPolicy: repairPolicy,
    checkpointRevision: checkpointRevision ?? this.checkpointRevision,
    recovered: recovered,
    presentation: presentation ?? this.presentation,
  );
}

typedef AdventureCanStart = bool Function();
typedef AdventureCheckpointAppender =
    Future<void> Function(
      LearningActivityCheckpoint checkpoint, {
      required String ownerId,
    });

/// Coordinates Adventure's quiz-shaped presentation with canonical Learning
/// sessions, exact checkpoints, immutable pending evidence, and repair state.
final class AdventureRecoveryUseCases {
  AdventureRecoveryUseCases({
    required this.learning,
    required this.evidence,
    required this.canStartNewMission,
    required this.isRepairModeEligible,
    AdventureRepairSpacing? spacingForIdentity,
    AdventureCheckpointAppender? appendCheckpoint,
  }) {
    _spacingForIdentity = spacingForIdentity;
    _appendCheckpointAction =
        appendCheckpoint ?? learning.appendActivityCheckpoint;
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Adventure recovery and evidence must share Learning authority.',
      );
    }
  }

  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final AdventureCanStart canStartNewMission;
  final AdventureModeEligibility isRepairModeEligible;
  late final AdventureRepairSpacing? _spacingForIdentity;
  late final AdventureCheckpointAppender _appendCheckpointAction;

  static const int maximumRecoveryCheckpoints = 64;
  static const int terminalCheckpointReserve = 3;
  static const int _terminalRecoveryHistoryLimit = 100;
  static const int maximumOccurrences =
      maximumRecoveryCheckpoints - terminalCheckpointReserve - 1;
  static const int maximumOriginalItems = maximumOccurrences ~/ 2;

  AdventureLearningRun? _run;
  LearningSessionSummary? _completedSummary;
  _PendingAdventureCheckpointAppend? _pendingCheckpointWrite;

  AdventureLearningRun? get currentRun => _run;

  Future<AdventureLearningRun> startOrResume({
    required AdventureSessionPlanV1 plan,
    required String activeOwnerId,
    AdventurePromptCatalogSnapshotBuilder? buildPromptCatalogSnapshot,
  }) async {
    final ownerId = _canonical(activeOwnerId, 'activeOwnerId');
    await _requireActiveOwner(ownerId);

    final current = _run;
    if (current != null &&
        current.state.ownerId == ownerId &&
        current.state.phase != AdventureLearningCheckpointPhase.completed) {
      final refreshed = current._copyWith(presentation: _presentation());
      _run = refreshed;
      return refreshed;
    }

    final active = await learning.getActiveSession();
    if (active != null && active.activityType == mixedReviewActivityType) {
      final restored = await recoverExact(
        ownerId: ownerId,
        sessionId: active.id,
      );
      if (restored == null) {
        throw StateError('Accepted Adventure Learning session is unavailable.');
      }
      return restored;
    }

    final terminal = await _recoverLatestTerminalSession(ownerId);
    if (terminal != null) return terminal;

    if (!canStartNewMission()) {
      throw StateError('Adventure is off for new missions.');
    }
    _validatePlan(plan, ownerId);
    late AdventureLearningCheckpointState initialState;
    final policy = _newRepairPolicy();
    final session = await learning.startCheckpointedQuiz(
      activityType: mixedReviewActivityType,
      limit: plan.content.length,
      pinnedContent: <PinnedQuizContent>[
        for (final item in plan.content)
          PinnedQuizContent(
            identity: item,
            checksumSha256: plan.contentChecksumsSha256[item.id]!,
          ),
      ],
      sessionConfiguration: plan.configuration,
      initialState: (hydrated) async {
        final promptCatalogSnapshot = buildPromptCatalogSnapshot == null
            ? null
            : await buildPromptCatalogSnapshot(hydrated);
        initialState = AdventureLearningCheckpointState._validated(
          schemaVersion: promptCatalogSnapshot == null
              ? 1
              : AdventureLearningCheckpointState.currentSchemaVersion,
          sessionId: hydrated.id,
          ownerId: ownerId,
          mode: plan.mode,
          content: plan.content,
          contentChecksumsSha256: plan.contentChecksumsSha256,
          currentOriginalIndex: 0,
          nextOccurrenceOrdinal: 1,
          phase: AdventureLearningCheckpointPhase.active,
          pendingOccurrence: null,
          terminalAtUtc: null,
          summaryPresented: false,
          promptCatalogSnapshot: promptCatalogSnapshot,
          repairPolicySnapshot: policy.snapshot(),
        );
        _validateHydratedSession(hydrated, initialState);
        return initialState.toJson();
      },
    );
    if (session.isEmpty) {
      throw StateError('Pinned Adventure Learning content is unavailable.');
    }
    _validateHydratedSession(session, initialState);
    final run = AdventureLearningRun._(
      session: session,
      state: initialState,
      pendingEvidence: null,
      pendingClose: null,
      repairPolicy: policy,
      checkpointRevision: 1,
      recovered: false,
      presentation: AdventureLearningPresentation.adventure,
    );
    _run = run;
    _completedSummary = null;
    return run;
  }

  Future<AdventureLearningRun?> _recoverLatestTerminalSession(
    String ownerId,
  ) async {
    final session = await findLatestPendingTerminal(ownerId: ownerId);
    return session == null
        ? null
        : recoverExact(ownerId: ownerId, sessionId: session.id);
  }

  /// Read-only discovery for the Standard Learn surface. It remains
  /// available while Adventure presentation is hidden or emergency-off.
  Future<LearningSessionSummary?> findLatestPendingTerminal({
    required String ownerId,
  }) async {
    final canonicalOwnerId = _canonical(ownerId, 'ownerId');
    await _requireActiveOwner(canonicalOwnerId);
    final history = await learning.listCompletedActivitySessionHistory(
      activityType: mixedReviewActivityType,
      limit: _terminalRecoveryHistoryLimit,
    );
    for (final session in history) {
      final recovery = await learning.loadExactActivityRecovery(
        ownerId: canonicalOwnerId,
        sessionId: session.id,
        activityType: mixedReviewActivityType,
      );
      final checkpoint = recovery?.checkpoint;
      if (recovery == null || checkpoint == null) {
        throw StateError('Exact Adventure Learning checkpoint is unavailable.');
      }
      final state = AdventureLearningCheckpointState.fromJson(checkpoint.state);
      _validateRecovery(recovery, checkpoint, state);
      final requiresRecovery =
          state.phase == AdventureLearningCheckpointPhase.closing ||
          state.phase == AdventureLearningCheckpointPhase.completed &&
              !state.summaryPresented;
      if (requiresRecovery) return recovery.session;
    }
    return null;
  }

  Future<AdventureLearningRun?> recoverExact({
    required String ownerId,
    required String sessionId,
  }) async {
    final canonicalOwnerId = _canonical(ownerId, 'ownerId');
    final canonicalSessionId = _canonical(sessionId, 'sessionId');
    await _requireActiveOwner(canonicalOwnerId);
    final recovery = await learning.loadExactActivityRecovery(
      ownerId: canonicalOwnerId,
      sessionId: canonicalSessionId,
      activityType: mixedReviewActivityType,
    );
    if (recovery == null) return null;
    final checkpoint = recovery.checkpoint;
    if (checkpoint == null) {
      throw StateError('Exact Adventure Learning checkpoint is unavailable.');
    }
    final state = AdventureLearningCheckpointState.fromJson(checkpoint.state);
    _validateRecovery(recovery, checkpoint, state);
    final session = await learning.reconstructPinnedQuizSession(
      session: recovery.session,
      content: state.content,
      contentChecksumsSha256: state.contentChecksumsSha256,
    );
    _validateHydratedSession(session, state);
    final policy = AdventureRepairPolicy.restore(
      state.repairPolicySnapshot,
      isModeEligible: isRepairModeEligible,
      spacingForIdentity: _spacingForIdentity,
    );
    final frozenPending = state.pendingOccurrence?.evidence;
    final pending = frozenPending == null
        ? null
        : evidence.restore(frozenPending, ownerId: state.ownerId);
    final pendingClose = state.phase == AdventureLearningCheckpointPhase.closing
        ? learning.restoreSessionClose(
            sessionId: state.sessionId,
            completedAtUtc: state.terminalAtUtc!,
            ownerId: state.ownerId,
          )
        : null;
    final run = AdventureLearningRun._(
      session: session,
      state: state,
      pendingEvidence: pending,
      pendingClose: pendingClose,
      repairPolicy: policy,
      checkpointRevision: checkpoint.revision,
      recovered: true,
      presentation: AdventureLearningPresentation.standard,
    );
    _run = run;
    _completedSummary =
        state.phase == AdventureLearningCheckpointPhase.completed
        ? recovery.session
        : null;
    return run;
  }

  Future<void> checkpointPendingEvidence({
    required PendingCurrentActivityEvidence pending,
    required int originalIndex,
    required AdventureLearningItemRole role,
    required LessonMode mode,
  }) async {
    final run = _requireWritableRun();
    await _requireActiveOwner(run.state.ownerId);
    if (run.state.phase != AdventureLearningCheckpointPhase.active ||
        !pending.belongsToLearningAuthority(learning) ||
        pending.sessionId != run.session.id ||
        pending.actorIdentity != null &&
            pending.actorIdentity != run.state.ownerId ||
        originalIndex != run.state.currentOriginalIndex) {
      throw StateError(
        'Pending evidence does not belong to this Adventure run.',
      );
    }
    final frozen = await pending.freezeForRecovery();
    final identities = run.state.content
        .where((identity) => identity.id == frozen.wordId)
        .toList(growable: false);
    if (identities.length != 1 ||
        frozen.ownerId != run.state.ownerId ||
        frozen.sessionId != run.state.sessionId ||
        frozen.attemptNumber != run.state.nextOccurrenceOrdinal) {
      throw StateError('Pending evidence identity is not the next occurrence.');
    }
    final occurrence = AdventureLearningPendingOccurrence._validated(
      identity: identities.single,
      role: role,
      mode: mode,
      promptVariant: frozen.promptMode,
      ordinal: run.state.nextOccurrenceOrdinal,
      evidence: frozen,
      checkpointOnlyOutcome: null,
    );
    final next = run.state.transition(
      currentOriginalIndex: originalIndex,
      phase: AdventureLearningCheckpointPhase.pendingOccurrence,
      pendingOccurrence: occurrence,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    _requireOccurrenceCheckpointBudget(run);
    await _appendCheckpoint(run: run, state: next, pendingEvidence: pending);
  }

  Future<void> checkpointFlashcardRepair({
    required ContentIdentity identity,
    required int originalIndex,
  }) async {
    final run = _requireWritableRun();
    await _requireActiveOwner(run.state.ownerId);
    final ticket = run.repairPolicy.dueRepairs
        .where((candidate) => candidate.identity == identity)
        .toList(growable: false);
    if (ticket.length != 1 ||
        ticket.single.repairMode != LessonMode.flashcard ||
        ticket.single.repairPromptVariant != 'flashcardExposure') {
      throw StateError('No exact flashcard repair is due for this content.');
    }
    await _checkpointNonEvidenceOccurrence(
      run: run,
      identity: identity,
      role: AdventureLearningItemRole.repair,
      mode: LessonMode.flashcard,
      promptVariant: 'flashcardExposure',
      originalIndex: originalIndex,
      outcome: AdventureAttemptOutcome.exposure,
    );
  }

  Future<void> checkpointSkippedOccurrence({
    required ContentIdentity identity,
    required int originalIndex,
    required AdventureLearningItemRole role,
    required LessonMode mode,
    required String promptVariant,
  }) async {
    final run = _requireWritableRun();
    await _requireActiveOwner(run.state.ownerId);
    await _checkpointNonEvidenceOccurrence(
      run: run,
      identity: identity,
      originalIndex: originalIndex,
      role: role,
      mode: mode,
      promptVariant: promptVariant,
      outcome: AdventureAttemptOutcome.skipped,
    );
  }

  Future<void> _checkpointNonEvidenceOccurrence({
    required AdventureLearningRun run,
    required ContentIdentity identity,
    required int originalIndex,
    required AdventureLearningItemRole role,
    required LessonMode mode,
    required String promptVariant,
    required AdventureAttemptOutcome outcome,
  }) async {
    if (run.state.phase != AdventureLearningCheckpointPhase.active ||
        originalIndex != run.state.currentOriginalIndex) {
      throw StateError('Non-evidence occurrence is not the next item.');
    }
    final occurrence = AdventureLearningPendingOccurrence._validated(
      identity: identity,
      role: role,
      mode: mode,
      promptVariant: promptVariant,
      ordinal: run.state.nextOccurrenceOrdinal,
      evidence: null,
      checkpointOnlyOutcome: outcome,
    );
    final next = run.state.transition(
      currentOriginalIndex: originalIndex,
      phase: AdventureLearningCheckpointPhase.pendingOccurrence,
      pendingOccurrence: occurrence,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    _requireOccurrenceCheckpointBudget(run);
    await _appendCheckpoint(run: run, state: next);
  }

  AdventureRepairDecision acceptPendingOccurrence(
    AdventureRepairAttempt attempt, {
    required int nextOriginalIndex,
    required int remainingOriginalItems,
  }) {
    final run = _requireWritableRun();
    final occurrence = run.state.pendingOccurrence;
    if (run.state.phase != AdventureLearningCheckpointPhase.pendingOccurrence ||
        occurrence == null ||
        occurrence.identity != attempt.identity ||
        occurrence.mode != attempt.mode ||
        occurrence.promptVariant != attempt.promptVariant ||
        (occurrence.role == AdventureLearningItemRole.repair) !=
            attempt.isRepair) {
      throw StateError('Attempt does not match the pending occurrence.');
    }
    final expectedNextOriginalIndex =
        occurrence.role == AdventureLearningItemRole.original
        ? run.state.currentOriginalIndex + 1
        : run.state.currentOriginalIndex;
    if (nextOriginalIndex != expectedNextOriginalIndex ||
        nextOriginalIndex < 0 ||
        nextOriginalIndex > run.state.content.length ||
        remainingOriginalItems !=
            run.state.content.length - nextOriginalIndex) {
      throw StateError('Occurrence cursor does not match pinned content.');
    }
    final frozen = occurrence.evidence;
    if (frozen == null) {
      if (attempt.canonicalEvidenceCommitted ||
          attempt.sourceEvidenceId != null ||
          attempt.evidenceClass != null ||
          occurrence.checkpointOnlyOutcome == null ||
          attempt.outcome != occurrence.checkpointOnlyOutcome) {
        throw StateError('Checkpoint-only repair semantics changed.');
      }
    } else {
      final pending = run.pendingEvidence;
      if (pending == null ||
          !pending.isCommitted ||
          !attempt.canonicalEvidenceCommitted ||
          attempt.sourceEvidenceId != frozen.sourceEvidenceId ||
          attempt.evidenceClass != frozen.declaredEvidenceClass ||
          !_outcomeMatchesFrozenEvidence(attempt.outcome, frozen)) {
        throw StateError('Canonical occurrence evidence is not committed.');
      }
    }
    final decision = run.repairPolicy.recordAttempt(
      attempt: attempt,
      remainingOriginalItems: remainingOriginalItems,
    );
    final next = run.state.transition(
      currentOriginalIndex: nextOriginalIndex,
      nextOccurrenceOrdinal: run.state.nextOccurrenceOrdinal + 1,
      phase: AdventureLearningCheckpointPhase.active,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    _run = run._copyWith(
      state: next,
      clearPendingEvidence: true,
      presentation: _presentation(),
    );
    return decision;
  }

  Future<LearningSessionSummary> completeSession(
    PendingLearningSessionClose close,
  ) async {
    await checkpointSessionClose(close);
    final run = _requireRun();
    if (run.state.phase == AdventureLearningCheckpointPhase.completed) {
      return _loadCompletedSummary(run, close.completedAtUtc);
    }
    final summary = close.requiresRetry
        ? await close.retry()
        : await close.finish();
    await acknowledgeSessionClosed(close: close, summary: summary);
    return summary;
  }

  /// Persists the exact terminal identity before the Unified Lesson shell is
  /// allowed to close Learning. This split lets route retirement safely finish
  /// an already accepted close without bypassing the activity checkpoint.
  Future<void> checkpointSessionClose(PendingLearningSessionClose close) async {
    var run = _requireRun();
    await _requireActiveOwner(run.state.ownerId);
    _validateClose(run, close);
    close.pinOwner(run.state.ownerId);
    final terminalAtUtc = close.completedAtUtc;
    if (run.state.phase == AdventureLearningCheckpointPhase.completed) {
      if (run.state.terminalAtUtc != terminalAtUtc) {
        throw StateError('Adventure completion identity changed.');
      }
      return;
    }
    if (run.state.phase == AdventureLearningCheckpointPhase.pendingOccurrence) {
      throw StateError('Pending occurrence must resolve before session close.');
    }
    if (run.state.phase == AdventureLearningCheckpointPhase.closing) {
      if (run.state.terminalAtUtc != terminalAtUtc) {
        throw StateError('Adventure completion identity changed.');
      }
      if (run.pendingClose == null) {
        _run = run._copyWith(pendingClose: close);
      }
      return;
    }
    if (run.state.currentOriginalIndex != run.state.content.length) {
      throw StateError('All original items must resolve before session close.');
    }
    run.repairPolicy.deferRemaining();
    final closing = run.state.transition(
      currentOriginalIndex: run.state.currentOriginalIndex,
      phase: AdventureLearningCheckpointPhase.closing,
      terminalAtUtc: terminalAtUtc,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    await _appendCheckpoint(
      run: run,
      state: closing,
      terminalAtUtc: terminalAtUtc,
      clearPending: true,
      pendingClose: close,
    );
  }

  /// Acknowledges a Learning-owned completion after the shell has committed
  /// it, authenticating the durable session before the terminal checkpoint.
  Future<void> acknowledgeSessionClosed({
    required PendingLearningSessionClose close,
    required LearningSessionSummary summary,
  }) async {
    final run = _requireRun();
    await _requireActiveOwner(run.state.ownerId);
    _validateClose(run, close);
    close.pinOwner(run.state.ownerId);
    final terminalAtUtc = close.completedAtUtc;
    if (run.state.phase == AdventureLearningCheckpointPhase.completed) {
      if (run.state.terminalAtUtc != terminalAtUtc) {
        throw StateError('Adventure completion identity changed.');
      }
      final durable = await _loadCanonicalCompletedSummary(run);
      _requireCanonicalSummary(
        summary: summary,
        durable: durable,
        terminalAtUtc: terminalAtUtc,
      );
      _completedSummary = durable;
      return;
    }
    if (run.state.phase != AdventureLearningCheckpointPhase.closing ||
        run.state.terminalAtUtc != terminalAtUtc) {
      throw StateError('Adventure close was not checkpointed.');
    }
    final durable = await _loadCanonicalCompletedSummary(run);
    _requireCanonicalSummary(
      summary: summary,
      durable: durable,
      terminalAtUtc: terminalAtUtc,
    );
    final completed = run.state.transition(
      currentOriginalIndex: run.state.currentOriginalIndex,
      phase: AdventureLearningCheckpointPhase.completed,
      terminalAtUtc: terminalAtUtc,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    await _appendCheckpoint(
      run: run,
      state: completed,
      terminalAtUtc: terminalAtUtc,
      terminalAcknowledged: true,
      clearPending: true,
      clearPendingClose: true,
    );
    _completedSummary = durable;
  }

  void _validateClose(
    AdventureLearningRun run,
    PendingLearningSessionClose close,
  ) {
    if (!close.belongsToLearningAuthority(learning) ||
        close.sessionId != run.session.id) {
      throw StateError('Session close does not belong to this Adventure run.');
    }
  }

  Future<LearningSessionSummary> _loadCompletedSummary(
    AdventureLearningRun run,
    DateTime terminalAtUtc,
  ) async {
    if (run.state.terminalAtUtc != terminalAtUtc) {
      throw StateError('Adventure completion identity changed.');
    }
    final summary =
        _completedSummary ?? await _loadCanonicalCompletedSummary(run);
    if (summary.id != run.state.sessionId ||
        summary.ownerId != run.state.ownerId ||
        summary.activityType != mixedReviewActivityType ||
        summary.state != 'completed' ||
        summary.endedAtUtc != terminalAtUtc) {
      throw StateError('Adventure completion identity changed.');
    }
    _completedSummary = summary;
    return summary;
  }

  /// Reads the completed summary from canonical Learning state. Adventure
  /// never reconstructs scores or counts from its presentation checkpoint.
  Future<LearningSessionSummary> loadCompletedSummary() {
    final run = _requireRun();
    final terminalAtUtc = run.state.terminalAtUtc;
    if (run.state.phase != AdventureLearningCheckpointPhase.completed ||
        terminalAtUtc == null) {
      throw StateError('Adventure Learning run is not completed.');
    }
    return _loadCompletedSummary(run, terminalAtUtc);
  }

  Future<LearningSessionSummary> _loadCanonicalCompletedSummary(
    AdventureLearningRun run,
  ) async {
    final exact = await learning.loadExactActivityRecovery(
      ownerId: run.state.ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );
    final durable = exact?.session;
    if (durable == null ||
        durable.id != run.state.sessionId ||
        durable.ownerId != run.state.ownerId ||
        durable.activityType != mixedReviewActivityType ||
        durable.state != 'completed') {
      throw StateError('Completed Adventure Learning session is unavailable.');
    }
    return durable;
  }

  static void _requireCanonicalSummary({
    required LearningSessionSummary summary,
    required LearningSessionSummary durable,
    required DateTime terminalAtUtc,
  }) {
    if (summary.id != durable.id ||
        summary.ownerId != durable.ownerId ||
        summary.activityType != durable.activityType ||
        summary.state != durable.state ||
        summary.startedAtUtc != durable.startedAtUtc ||
        summary.endedAtUtc != terminalAtUtc ||
        durable.endedAtUtc != terminalAtUtc ||
        summary.correctCount != durable.correctCount ||
        summary.wrongCount != durable.wrongCount ||
        summary.score != durable.score ||
        summary.appVersion != durable.appVersion ||
        summary.buildId != durable.buildId ||
        summary.sessionConfiguration != durable.sessionConfiguration ||
        summary.configurationActiveEffort !=
            durable.configurationActiveEffort) {
      throw StateError('Learning completion acknowledgement is not canonical.');
    }
  }

  Future<void> acknowledgeSummaryPresented() async {
    final run = _requireRun();
    await _requireActiveOwner(run.state.ownerId);
    if (run.state.phase != AdventureLearningCheckpointPhase.completed) {
      throw StateError('Only a completed mixed-review summary can be shown.');
    }
    if (run.state.summaryPresented) return;
    final next = run.state.transition(
      currentOriginalIndex: run.state.currentOriginalIndex,
      phase: AdventureLearningCheckpointPhase.completed,
      terminalAtUtc: run.state.terminalAtUtc,
      summaryPresented: true,
      repairPolicySnapshot: run.repairPolicy.snapshot(),
    );
    await _appendCheckpoint(
      run: run,
      state: next,
      terminalAtUtc: run.state.terminalAtUtc,
      terminalAcknowledged: true,
      clearPending: true,
      clearPendingClose: true,
    );
  }

  AdventureLearningRun _requireRun() {
    final run = _run;
    if (run == null) throw StateError('No Adventure Learning run is accepted.');
    return run;
  }

  AdventureLearningRun _requireWritableRun() {
    final run = _requireRun();
    if (run.state.phase == AdventureLearningCheckpointPhase.closing ||
        run.state.phase == AdventureLearningCheckpointPhase.completed) {
      throw StateError('Adventure Learning run is already closing.');
    }
    return run;
  }

  Future<void> _appendCheckpoint({
    required AdventureLearningRun run,
    required AdventureLearningCheckpointState state,
    PendingCurrentActivityEvidence? pendingEvidence,
    bool clearPending = false,
    PendingLearningSessionClose? pendingClose,
    bool clearPendingClose = false,
    DateTime? terminalAtUtc,
    bool terminalAcknowledged = false,
  }) async {
    await _requireActiveOwner(run.state.ownerId);
    final revision = run.checkpointRevision + 1;
    if (revision > maximumRecoveryCheckpoints) {
      throw StateError('Mixed-review checkpoint budget is exhausted.');
    }
    final existing = _pendingCheckpointWrite;
    final append =
        existing ??
        _PendingAdventureCheckpointAppend(
          checkpoint: LearningActivityCheckpoint(
            sessionId: run.session.id,
            activityType: mixedReviewActivityType,
            revision: revision,
            occurredAtUtc: learning.nowUtc(),
            state: state.toJson(),
            terminalAtUtc: terminalAtUtc,
            terminalAcknowledged: terminalAcknowledged,
          ),
          run: run,
          state: state,
          pendingEvidence: pendingEvidence,
          clearPendingEvidence: clearPending,
          pendingClose: pendingClose,
          clearPendingClose: clearPendingClose,
        );
    if (existing != null &&
        (existing.checkpoint.sessionId != run.session.id ||
            existing.checkpoint.revision != revision ||
            jsonEncode(existing.checkpoint.state) !=
                jsonEncode(state.toJson()) ||
            existing.checkpoint.terminalAtUtc != terminalAtUtc ||
            existing.checkpoint.terminalAcknowledged != terminalAcknowledged)) {
      throw StateError('The exact failed checkpoint must be retried first.');
    }
    _pendingCheckpointWrite = append;
    await _appendCheckpointAction(
      append.checkpoint,
      ownerId: append.run.state.ownerId,
    );
    _pendingCheckpointWrite = null;
    _run = append.run._copyWith(
      state: append.state,
      pendingEvidence: append.pendingEvidence,
      clearPendingEvidence: append.clearPendingEvidence,
      pendingClose: append.pendingClose,
      clearPendingClose: append.clearPendingClose,
      checkpointRevision: append.checkpoint.revision,
      presentation: _presentation(),
    );
  }

  void _requireOccurrenceCheckpointBudget(AdventureLearningRun run) {
    if (run.state.nextOccurrenceOrdinal > maximumOccurrences ||
        run.checkpointRevision + 1 >
            maximumRecoveryCheckpoints - terminalCheckpointReserve) {
      throw StateError('Mixed-review occurrence exceeds checkpoint budget.');
    }
  }

  static bool _outcomeMatchesFrozenEvidence(
    AdventureAttemptOutcome outcome,
    FrozenPendingCurrentActivityEvidence frozen,
  ) {
    if (!frozen.isCorrect) {
      return outcome == AdventureAttemptOutcome.incorrect;
    }
    return switch (frozen.declaredEvidenceClass) {
      EvidenceClass.guidedPractice => outcome == AdventureAttemptOutcome.guided,
      EvidenceClass.exposure => outcome == AdventureAttemptOutcome.exposure,
      _ => outcome == AdventureAttemptOutcome.correct,
    };
  }

  Future<void> _requireActiveOwner(String expectedOwnerId) async {
    final owner = await learning.owners.getOrCreateActiveOwner();
    if (owner.id != expectedOwnerId) {
      throw StateError('Adventure Learning owner is no longer active.');
    }
  }

  AdventureLearningPresentation _presentation() =>
      _run?.recovered == true || !canStartNewMission()
      ? AdventureLearningPresentation.standard
      : AdventureLearningPresentation.adventure;

  AdventureRepairPolicy _newRepairPolicy() => AdventureRepairPolicy(
    isModeEligible: isRepairModeEligible,
    spacingForIdentity: _spacingForIdentity,
  );

  void _validatePlan(AdventureSessionPlanV1 plan, String ownerId) {
    if (plan.ownerId != ownerId || plan.configuration.ownerId != ownerId) {
      throw StateError('Adventure plan owner is no longer active.');
    }
    if (plan.mode != plan.configuration.mode ||
        plan.configuration.itemCount != plan.content.length ||
        plan.content.isEmpty ||
        plan.content.length > maximumOriginalItems) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.incompatibleConfiguration,
      );
    }
    final ids = <String>{};
    for (final identity in plan.content) {
      final checksum = plan.contentChecksumsSha256[identity.id];
      if (identity.type != ContentType.lexicalMetadata ||
          identity.revision <= 0 ||
          !_isCanonical(identity.id) ||
          !ids.add(identity.id) ||
          checksum == null ||
          !AdventureLearningCheckpointState._sha256.hasMatch(checksum)) {
        throw const AdventureSessionPlanException(
          AdventureSessionPlanFailure.unresolvedContent,
        );
      }
    }
    if (plan.contentChecksumsSha256.length != ids.length ||
        !plan.contentChecksumsSha256.keys.every(ids.contains)) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.unresolvedContent,
      );
    }
  }

  void _validateHydratedSession(
    QuizSession session,
    AdventureLearningCheckpointState state,
  ) {
    if (session.id != state.sessionId ||
        session.ownerId != state.ownerId ||
        session.questions.length != state.content.length ||
        session.sessionConfiguration?.ownerId != state.ownerId ||
        session.sessionConfiguration?.mode != state.mode ||
        session.sessionConfiguration?.itemCount != state.content.length) {
      throw StateError('Adventure Learning session identity is corrupt.');
    }
    for (var index = 0; index < state.content.length; index += 1) {
      final expected = state.content[index];
      final actual = session.questions[index].word;
      if (actual.id != expected.id ||
          actual.contentRevision != expected.revision ||
          actual.contentChecksumSha256 !=
              state.contentChecksumsSha256[expected.id]) {
        throw StateError('Adventure Learning content identity changed.');
      }
    }
  }

  void _validateRecovery(
    LearningActivityRecovery recovery,
    LearningActivityCheckpoint checkpoint,
    AdventureLearningCheckpointState state,
  ) {
    final session = recovery.session;
    if (session.id != state.sessionId ||
        session.ownerId != state.ownerId ||
        session.activityType != mixedReviewActivityType ||
        checkpoint.sessionId != state.sessionId ||
        checkpoint.activityType != mixedReviewActivityType ||
        checkpoint.revision < 1 ||
        checkpoint.revision > maximumRecoveryCheckpoints ||
        checkpoint.revision != _expectedCheckpointRevision(state) ||
        checkpoint.terminalAtUtc != state.terminalAtUtc) {
      throw StateError('Adventure Learning recovery identity is corrupt.');
    }
    final validLifecycle = switch (state.phase) {
      AdventureLearningCheckpointPhase.active ||
      AdventureLearningCheckpointPhase.pendingOccurrence =>
        session.state == 'active' &&
            checkpoint.terminalAtUtc == null &&
            !checkpoint.terminalAcknowledged,
      AdventureLearningCheckpointPhase.closing =>
        (session.state == 'active' || session.state == 'completed') &&
            checkpoint.terminalAtUtc != null &&
            !checkpoint.terminalAcknowledged,
      AdventureLearningCheckpointPhase.completed =>
        session.state == 'completed' &&
            checkpoint.terminalAtUtc != null &&
            checkpoint.terminalAcknowledged,
    };
    if (!validLifecycle ||
        recovery.attempts.any(
          (attempt) =>
              attempt.ownerId != state.ownerId ||
              attempt.sessionId != state.sessionId ||
              !state.content.any((item) => item.id == attempt.wordId),
        )) {
      throw StateError('Adventure Learning recovery state is corrupt.');
    }
  }

  static String _canonical(String value, String field) {
    if (!_isCanonical(value)) {
      throw ArgumentError.value(value, field, 'must be canonical');
    }
    return value;
  }

  static bool _isCanonical(String value) =>
      value.isNotEmpty && value == value.trim() && value.runes.length <= 256;

  static int _expectedCheckpointRevision(
    AdventureLearningCheckpointState state,
  ) => switch (state.phase) {
    AdventureLearningCheckpointPhase.active => 1,
    AdventureLearningCheckpointPhase.pendingOccurrence =>
      state.nextOccurrenceOrdinal + 1,
    AdventureLearningCheckpointPhase.closing => state.nextOccurrenceOrdinal + 1,
    AdventureLearningCheckpointPhase.completed =>
      state.nextOccurrenceOrdinal + (state.summaryPresented ? 3 : 2),
  };
}

final class _PendingAdventureCheckpointAppend {
  const _PendingAdventureCheckpointAppend({
    required this.checkpoint,
    required this.run,
    required this.state,
    required this.pendingEvidence,
    required this.clearPendingEvidence,
    required this.pendingClose,
    required this.clearPendingClose,
  });

  final LearningActivityCheckpoint checkpoint;
  final AdventureLearningRun run;
  final AdventureLearningCheckpointState state;
  final PendingCurrentActivityEvidence? pendingEvidence;
  final bool clearPendingEvidence;
  final PendingLearningSessionClose? pendingClose;
  final bool clearPendingClose;
}

Map<String, Object?> _encodeLearningIdentity(ContentIdentity identity) =>
    <String, Object?>{
      'type': identity.type.name,
      'id': identity.id,
      'revision': identity.revision,
    };

ContentIdentity _decodeLearningIdentity(Object? raw) {
  final json = AdventureLearningCheckpointState._requiredMap(raw, 'identity');
  const keys = <String>{'type', 'id', 'revision'};
  if (json.length != keys.length ||
      !json.keys.every(keys.contains) ||
      json['type'] != ContentType.lexicalMetadata.name ||
      json['id'] is! String ||
      json['revision'] is! int) {
    throw const FormatException('invalid mixed-review content identity');
  }
  final identity = ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: json['id']! as String,
    revision: json['revision']! as int,
  );
  if (identity.id.isEmpty ||
      identity.id != identity.id.trim() ||
      identity.revision <= 0) {
    throw const FormatException('invalid mixed-review content identity');
  }
  return identity;
}

Map<String, Object?> _freezeJsonMap(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final entry in source.entries)
        entry.key: _freezeJsonValue(entry.value),
    });

Object? _freezeJsonValue(Object? value) {
  if (value is Map) {
    late final Map<String, Object?> map;
    try {
      map = value.cast<String, Object?>();
    } on Object {
      throw const FormatException('Adventure checkpoint JSON keys are invalid');
    }
    return _freezeJsonMap(map);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw FormatException(
    'unsupported Adventure checkpoint JSON value ${value.runtimeType}',
  );
}
