import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'pair_matching_launch.dart';

/// Explicit internal delivery authority, checked inside the start transaction.
abstract interface class PairMatchingStartCapability {
  void requireAllowed(PairMatchingPlanV1 plan);
}

final class PairLexicalItem {
  PairLexicalItem({
    required this.wordId,
    required this.contentRevision,
    required this.checksum,
    required this.spelling,
    required this.meaning,
    required this.sourceLocale,
    required this.targetLocale,
    required Iterable<PairSourceReason> sourceReasons,
  }) : sourceReasons = Set<PairSourceReason>.unmodifiable(sourceReasons) {
    if (wordId.isEmpty ||
        wordId != wordId.trim() ||
        wordId.length > 256 ||
        contentRevision < 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        spelling.trim().isEmpty ||
        meaning.trim().isEmpty ||
        spelling.length > 256 ||
        meaning.length > 256 ||
        this.sourceReasons.isEmpty) {
      throw ArgumentError('Invalid Pair lexical pin');
    }
  }
  final String wordId;
  final int contentRevision;
  final String checksum;
  final String spelling;
  final String meaning;
  final String sourceLocale;
  final String targetLocale;
  final Set<PairSourceReason> sourceReasons;
  String get canonicalIdentity => '$wordId:$contentRevision';
  PairLexicalItem withReasons(Iterable<PairSourceReason> reasons) =>
      PairLexicalItem(
        wordId: wordId,
        contentRevision: contentRevision,
        checksum: checksum,
        spelling: spelling,
        meaning: meaning,
        sourceLocale: sourceLocale,
        targetLocale: targetLocale,
        sourceReasons: reasons,
      );
  Map<String, Object?> toJson() => Map.unmodifiable({
    'wordId': wordId,
    'contentRevision': contentRevision,
    'checksum': checksum,
    'spelling': spelling,
    'meaning': meaning,
    'sourceLocale': sourceLocale,
    'targetLocale': targetLocale,
    'sourceReasons': List.unmodifiable(
      (sourceReasons.toList()..sort((a, b) => a.index.compareTo(b.index))).map(
        (r) => r.name,
      ),
    ),
  });
  static PairLexicalItem fromJson(Object? value) {
    final j = pairJson(value, {
      'wordId',
      'contentRevision',
      'checksum',
      'spelling',
      'meaning',
      'sourceLocale',
      'targetLocale',
      'sourceReasons',
    });
    return PairLexicalItem(
      wordId: j['wordId'] as String,
      contentRevision: j['contentRevision'] as int,
      checksum: j['checksum'] as String,
      spelling: j['spelling'] as String,
      meaning: j['meaning'] as String,
      sourceLocale: j['sourceLocale'] as String,
      targetLocale: j['targetLocale'] as String,
      sourceReasons: (j['sourceReasons'] as List).map(
        (r) => PairSourceReason.values.byName(r as String),
      ),
    );
  }
}

/// Renderer independent, deeply immutable semantic contract. Versioned shuffle
/// uses a SHA-256 ordering, avoiding dependence on Dart Random implementation.
final class PairMatchingPlanV1 {
  PairMatchingPlanV1({
    required this.ownerId,
    required Iterable<PairLexicalItem> orderedLexicalItems,
    required this.direction,
    required this.density,
    required this.shuffleSeed,
    required this.timerPreset,
    required this.allowlistVersion,
    required this.learningSessionId,
    required this.entryKind,
    required this.sourceSnapshotId,
    required this.createdAtUtc,
    this.sessionPurpose = PairSessionPurpose.learning,
    this.sourceSessionId,
  }) : orderedLexicalItems = List.unmodifiable(orderedLexicalItems) {
    if (ownerId.isEmpty ||
        ownerId != ownerId.trim() ||
        ownerId.length > 256 ||
        learningSessionId.isEmpty ||
        learningSessionId.length > 256 ||
        sourceSnapshotId.isEmpty ||
        sourceSnapshotId.length > 256 ||
        !createdAtUtc.isUtc ||
        createdAtUtc.millisecondsSinceEpoch < 0 ||
        createdAtUtc.microsecondsSinceEpoch % 1000 != 0 ||
        (sourceSessionId != null &&
            (sourceSessionId!.isEmpty ||
                sourceSessionId != sourceSessionId!.trim() ||
                sourceSessionId!.length > 256)) ||
        allowlistVersion.isEmpty ||
        allowlistVersion.length > 256 ||
        shuffleSeed < 0 ||
        shuffleSeed > 0x7fffffff ||
        this.orderedLexicalItems.length != density.pairCount ||
        this.orderedLexicalItems.map((i) => i.wordId).toSet().length !=
            density.pairCount ||
        this.orderedLexicalItems.any(
          (i) => i.sourceLocale != 'en' || i.targetLocale != 'th',
        ) ||
        ((sessionPurpose == PairSessionPurpose.practiceReplay) !=
            (sourceSessionId != null))) {
      throw ArgumentError('Invalid exact Pair plan');
    }
    sourceOrder = _shuffle('source');
    targetOrder = _shuffle('target');
  }
  final String ownerId;
  final String learningSessionId;
  final PairSourceSurface entryKind;
  final String sourceSnapshotId;
  final DateTime createdAtUtc;
  final List<PairLexicalItem> orderedLexicalItems;
  final PairDirection direction;
  final PairDensity density;
  final int shuffleSeed;
  final PairTimerPreset timerPreset;
  final String allowlistVersion;
  final PairSessionPurpose sessionPurpose;
  final String? sourceSessionId;
  late final List<String> sourceOrder;
  late final List<String> targetOrder;
  int get repairPolicyVersion => 1;
  int get starPolicyVersion => 1;
  int get checkpointPolicyVersion => 6;
  String get planId => 'pair-plan:$planFingerprint';
  String get promptLocale => direction == PairDirection.enToTh ? 'en' : 'th';
  String get targetLocale => direction == PairDirection.enToTh ? 'th' : 'en';
  List<String> _shuffle(String side) {
    final ids = orderedLexicalItems.map((i) => i.wordId).toList();
    ids.sort(
      (a, b) => pairHash(
        jsonEncode([shuffleSeed, side, a]),
      ).compareTo(pairHash(jsonEncode([shuffleSeed, side, b]))),
    );
    return List.unmodifiable(ids);
  }

  Map<String, Object?> get _payload => Map.unmodifiable({
    'schemaVersion': 1,
    'ownerId': ownerId,
    'learningSessionId': learningSessionId,
    'entryKind': entryKind.name,
    'sourceSnapshotId': sourceSnapshotId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'checkpointPolicyVersion': checkpointPolicyVersion,
    'orderedLexicalItems': List.unmodifiable(
      orderedLexicalItems.map((i) => i.toJson()),
    ),
    'direction': direction.name,
    'density': density.name,
    'sourceOrder': sourceOrder,
    'targetOrder': targetOrder,
    'shuffleSeed': shuffleSeed,
    'shufflePolicyVersion': 1,
    'timerPreset': timerPreset.name,
    'repairPolicyVersion': repairPolicyVersion,
    'starPolicyVersion': starPolicyVersion,
    'allowlistVersion': allowlistVersion,
    'sessionPurpose': sessionPurpose.name,
    'sourceSessionId': sourceSessionId,
  });
  String get planFingerprint => pairHash(jsonEncode(_payload));
  Map<String, Object?> toJson() =>
      Map.unmodifiable({..._payload, 'planFingerprint': planFingerprint});
  String get stableSerialization => jsonEncode(toJson());
  static PairMatchingPlanV1 fromStableSerialization(String source) {
    if (source.length > 32768) {
      throw const FormatException('Pair plan too large');
    }
    try {
      final j = pairJson(jsonDecode(source), {
        'schemaVersion',
        'ownerId',
        'learningSessionId',
        'entryKind',
        'sourceSnapshotId',
        'createdAtUtc',
        'checkpointPolicyVersion',
        'orderedLexicalItems',
        'direction',
        'density',
        'sourceOrder',
        'targetOrder',
        'shuffleSeed',
        'shufflePolicyVersion',
        'timerPreset',
        'repairPolicyVersion',
        'starPolicyVersion',
        'allowlistVersion',
        'sessionPurpose',
        'sourceSessionId',
        'planFingerprint',
      });
      if (j['schemaVersion'] != 1 ||
          j['shufflePolicyVersion'] != 1 ||
          j['repairPolicyVersion'] != 1 ||
          j['starPolicyVersion'] != 1 ||
          j['checkpointPolicyVersion'] != 6) {
        throw const FormatException('Unknown Pair policy');
      }
      final p = PairMatchingPlanV1(
        ownerId: j['ownerId'] as String,
        learningSessionId: j['learningSessionId'] as String,
        entryKind: PairSourceSurface.values.byName(j['entryKind'] as String),
        sourceSnapshotId: j['sourceSnapshotId'] as String,
        createdAtUtc: DateTime.parse(j['createdAtUtc'] as String),
        orderedLexicalItems: (j['orderedLexicalItems'] as List).map(
          PairLexicalItem.fromJson,
        ),
        direction: PairDirection.values.byName(j['direction'] as String),
        density: PairDensity.values.byName(j['density'] as String),
        shuffleSeed: j['shuffleSeed'] as int,
        timerPreset: PairTimerPreset.values.byName(j['timerPreset'] as String),
        allowlistVersion: j['allowlistVersion'] as String,
        sessionPurpose: PairSessionPurpose.values.byName(
          j['sessionPurpose'] as String,
        ),
        sourceSessionId: j['sourceSessionId'] as String?,
      );
      if (p.stableSerialization != source) {
        throw const FormatException('Noncanonical or tampered Pair plan');
      }
      return p;
    } catch (_) {
      throw const FormatException('Invalid Pair plan');
    }
  }
}

String pairHash(String value) => sha256.convert(utf8.encode(value)).toString();
String pairSessionId(String ownerId, String operationId) =>
    'pair:${pairHash(jsonEncode([ownerId, operationId]))}';
Map<String, dynamic> pairJson(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    throw const FormatException('Unexpected Pair keys');
  }
  return value.cast<String, dynamic>();
}
