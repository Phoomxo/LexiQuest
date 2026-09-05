enum PairSourceSurface { learn, today, review, adventure, history }

enum PairDirection { enToTh, thToEn }

enum PairDensity { compact4, standard6 }

enum PairTimerPreset { off, seconds60, seconds90, seconds120 }

enum PairSessionPurpose { learning, practiceReplay }

enum PairSourceReason {
  dueSrs,
  incorrectAnswer,
  weakness,
  saved,
  newContent,
  reported,
}

enum PairDensityProvenance { learner, accessibility, oneTimeChoice, fallback }

/// Metadata within the existing owner/matching SessionConfiguration row.
/// A persisted choice or fallback consumes the one-time prompt; guardian
/// product policy is deliberately not stored as an invented receipt.
final class PairDensityPreference {
  PairDensityPreference({required this.density, required this.provenance}) {
    if (provenance == PairDensityProvenance.fallback &&
        density != PairDensity.compact4) {
      throw ArgumentError('Pair fallback density must be compact4');
    }
  }
  final PairDensity density;
  final PairDensityProvenance provenance;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'schemaVersion': 1,
    'density': density.name,
    'provenance': provenance.name,
  });
  static PairDensityPreference fromJson(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        !value.keys.toSet().containsAll({
          'schemaVersion',
          'density',
          'provenance',
        }) ||
        value['schemaVersion'] != 1) {
      throw const FormatException('Invalid Pair density metadata');
    }
    final density = PairDensity.values.byName(value['density'] as String);
    final provenance = PairDensityProvenance.values.byName(
      value['provenance'] as String,
    );
    if (provenance == PairDensityProvenance.fallback &&
        density != PairDensity.compact4) {
      throw const FormatException('Invalid fallback');
    }
    return PairDensityPreference(density: density, provenance: provenance);
  }
}

extension PairDensityCount on PairDensity {
  int get pairCount => this == PairDensity.compact4 ? 4 : 6;
}

/// Product inputs only. Guardian policy must be supplied by its owner;
/// neither Research nor inferred age/performance can supply an override.
final class PairDensityPreferences {
  const PairDensityPreferences({
    required this.ownerId,
    this.guardianOverride,
    this.learnerPreference,
    this.choiceHandled = false,
  });
  final String ownerId;
  final PairDensity? guardianOverride;
  final PairDensity? learnerPreference;
  final bool choiceHandled;
  PairDensity? resolve({PairDensity? requested, required bool canPrompt}) =>
      guardianOverride ??
      requested ??
      learnerPreference ??
      (canPrompt && !choiceHandled ? null : PairDensity.compact4);
}

final class PairMatchingLaunchIntent {
  PairMatchingLaunchIntent({
    required this.ownerId,
    required this.sourceSurface,
    required this.sourceSnapshotRef,
    required this.operationId,
    required this.createdAtUtc,
    this.requestedDirection = PairDirection.enToTh,
    this.requestedDensity,
    this.timerPreset = PairTimerPreset.off,
    this.sessionPurpose = PairSessionPurpose.learning,
    this.sourceSessionId,
  }) {
    for (final text in [ownerId, sourceSnapshotRef, operationId]) {
      if (text.isEmpty || text != text.trim() || text.length > 256) {
        throw ArgumentError(
          'Pair launch identity must be bounded canonical text',
        );
      }
    }
    if ((sessionPurpose == PairSessionPurpose.practiceReplay) !=
        (sourceSessionId != null)) {
      throw ArgumentError('Pair purpose/lineage mismatch');
    }
    if (!createdAtUtc.isUtc ||
        createdAtUtc.millisecondsSinceEpoch < 0 ||
        createdAtUtc.microsecondsSinceEpoch % 1000 != 0 ||
        (sourceSessionId != null &&
            (sourceSessionId!.trim().isEmpty ||
                sourceSessionId != sourceSessionId!.trim() ||
                sourceSessionId!.length > 256))) {
      throw ArgumentError('Invalid Pair time/lineage');
    }
  }
  final String ownerId;
  final PairSourceSurface sourceSurface;
  final String sourceSnapshotRef;
  final String operationId;
  final DateTime createdAtUtc;
  final PairDirection requestedDirection;
  final PairDensity? requestedDensity;
  final PairTimerPreset timerPreset;
  final PairSessionPurpose sessionPurpose;
  final String? sourceSessionId;
}
