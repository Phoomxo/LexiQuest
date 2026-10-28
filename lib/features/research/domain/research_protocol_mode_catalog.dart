import '../../learning/domain/evidence_context.dart';

/// One immutable, version-pinned mapping from a research protocol assignment
/// to the existing evidence-policy rollout authority.
final class ResearchProtocolModeMapping {
  const ResearchProtocolModeMapping({
    this.protocolId,
    required this.experimentId,
    required this.experimentVersion,
    required this.protocolVersion,
    required this.consentVersion,
    required this.mode,
  });

  final String? protocolId;
  final String experimentId;
  final int experimentVersion;
  final String protocolVersion;
  final int consentVersion;
  final EvidencePolicyRolloutMode mode;
}

/// Immutable versioned protocol-to-mode authority supplied at composition.
///
/// Both evidence-mode resolution and assignment delivery consume this single
/// catalog. Invalid or ambiguous mappings fail closed.
final class ResearchProtocolModeCatalog {
  const ResearchProtocolModeCatalog({
    required List<ResearchProtocolModeMapping> mappings,
  }) : this._withMappings(mappings);

  const ResearchProtocolModeCatalog._withMappings(this._mappings);

  final List<ResearchProtocolModeMapping> _mappings;

  bool get isEmpty => _mappings.isEmpty;

  ResearchProtocolModeMapping? lookup({
    required String? protocolId,
    required String experimentId,
    required int experimentVersion,
    required String protocolVersion,
    required int consentVersion,
  }) {
    _validateLookup(
      protocolId: protocolId,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      protocolVersion: protocolVersion,
    );
    _validatePositive(consentVersion, 'consentVersion');
    final mappings = _validatedMappings();
    ResearchProtocolModeMapping? result;
    for (final mapping in mappings) {
      if (mapping.experimentId == experimentId &&
          mapping.experimentVersion == experimentVersion &&
          mapping.protocolVersion == protocolVersion &&
          mapping.consentVersion == consentVersion &&
          (mapping.protocolId == null || mapping.protocolId == protocolId)) {
        if (result != null) {
          throw const FormatException(
            'Ambiguous research protocol mode mapping.',
          );
        }
        result = mapping;
      }
    }
    return result;
  }

  /// Resolves the one consent contract pinned by a persisted assignment.
  ///
  /// Assignment rows do not carry a consent version. Therefore more than one
  /// mapping for the same exact experiment/version/protocol is ambiguous and
  /// cannot authorize delivery.
  ResearchProtocolModeMapping? lookupForAssignment({
    required String experimentId,
    required int experimentVersion,
    required String protocolVersion,
  }) {
    _validateLookup(
      protocolId: null,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      protocolVersion: protocolVersion,
    );
    ResearchProtocolModeMapping? result;
    for (final mapping in _validatedMappings()) {
      if (mapping.experimentId == experimentId &&
          mapping.experimentVersion == experimentVersion &&
          mapping.protocolVersion == protocolVersion) {
        if (result != null) {
          throw const FormatException('Ambiguous assignment consent mapping.');
        }
        result = mapping;
      }
    }
    return result;
  }

  List<ResearchProtocolModeMapping> _validatedMappings() {
    final mappings = List<ResearchProtocolModeMapping>.unmodifiable(_mappings);
    final logicalKeys =
        <
          ({
            String? protocolId,
            String experimentId,
            int experimentVersion,
            String protocolVersion,
            int consentVersion,
          })
        >{};
    for (final mapping in mappings) {
      _validateMapping(mapping);
      final logicalKey = (
        protocolId: mapping.protocolId,
        experimentId: mapping.experimentId,
        experimentVersion: mapping.experimentVersion,
        protocolVersion: mapping.protocolVersion,
        consentVersion: mapping.consentVersion,
      );
      if (!logicalKeys.add(logicalKey)) {
        throw const FormatException(
          'Duplicate research protocol mode mapping.',
        );
      }
    }
    return mappings;
  }

  static void _validateLookup({
    required String? protocolId,
    required String experimentId,
    required int experimentVersion,
    required String protocolVersion,
  }) {
    _validateCanonicalIdentifier(experimentId, 'experimentId');
    _validatePositive(experimentVersion, 'experimentVersion');
    _validateCanonicalIdentifier(protocolVersion, 'protocolVersion');
    if (protocolId != null) {
      _validateCanonicalIdentifier(protocolId, 'protocolId');
    }
  }

  static void _validateMapping(ResearchProtocolModeMapping mapping) {
    final protocolId = mapping.protocolId;
    if (protocolId != null) {
      _validateCanonicalIdentifier(protocolId, 'protocolId');
    }
    _validateCanonicalIdentifier(mapping.experimentId, 'experimentId');
    _validatePositive(mapping.experimentVersion, 'experimentVersion');
    _validateCanonicalIdentifier(mapping.protocolVersion, 'protocolVersion');
    _validatePositive(mapping.consentVersion, 'consentVersion');
  }

  static void _validateCanonicalIdentifier(String value, String name) {
    if (!_isCanonical(value)) {
      throw FormatException('Invalid $name in research protocol mapping.');
    }
  }

  static void _validatePositive(int value, String name) {
    if (value <= 0) {
      throw FormatException('$name must be positive.');
    }
  }
}

bool _isCanonical(String value) {
  return value.isNotEmpty && value == value.trim() && value.runes.length <= 256;
}
