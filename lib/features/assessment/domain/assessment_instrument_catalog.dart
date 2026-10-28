import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';

enum AssessmentCatalogSourceState { approved, unsupported }

enum AssessmentCatalogReviewState { approved, draft, rejected }

final class AssessmentControlledResponse {
  const AssessmentControlledResponse({
    required this.responseCode,
    required this.isCorrect,
  });

  final String responseCode;
  final bool isCorrect;
}

final class AssessmentItemDefinition {
  const AssessmentItemDefinition({
    required this.itemId,
    required this.prompt,
    required this.wordId,
    required this.promptMode,
    required this.scoringRuleVersion,
    required this.responses,
  });

  final String itemId;
  final String prompt;
  final String wordId;
  final String promptMode;
  final String scoringRuleVersion;
  final Map<String, AssessmentControlledResponse> responses;
}

final class AssessmentInstrumentDefinition {
  AssessmentInstrumentDefinition({
    required this.instrumentId,
    required this.instrumentVersion,
    required this.formId,
    required this.formVersion,
    required this.formContentRevision,
    required this.sourceState,
    required this.reviewState,
    required this.protocolId,
    required this.experimentId,
    required this.experimentVersion,
    required this.contentRevision,
    required List<int> instrumentBytes,
    required List<int> formBytes,
    required this.instrumentChecksumSha256,
    required this.formChecksumSha256,
    required List<AssessmentItemDefinition> items,
  }) : instrumentBytes = List<int>.unmodifiable(instrumentBytes),
       formBytes = List<int>.unmodifiable(formBytes),
       items = List<AssessmentItemDefinition>.unmodifiable(
         items.map(
           (item) => AssessmentItemDefinition(
             itemId: item.itemId,
             prompt: item.prompt,
             wordId: item.wordId,
             promptMode: item.promptMode,
             scoringRuleVersion: item.scoringRuleVersion,
             responses: Map<String, AssessmentControlledResponse>.unmodifiable(
               item.responses,
             ),
           ),
         ),
       );

  final String instrumentId;
  final String instrumentVersion;
  final String formId;
  final String formVersion;
  final int formContentRevision;
  final AssessmentCatalogSourceState sourceState;
  final AssessmentCatalogReviewState reviewState;
  final String protocolId;
  final String experimentId;
  final int experimentVersion;
  final String contentRevision;
  final List<int> instrumentBytes;
  final List<int> formBytes;
  final String instrumentChecksumSha256;
  final String formChecksumSha256;
  final List<AssessmentItemDefinition> items;

  static List<int> canonicalFormBytes({
    required String instrumentId,
    required String instrumentVersion,
    required String formId,
    required String formVersion,
    required int formContentRevision,
    required List<AssessmentItemDefinition> items,
  }) => utf8.encode(
    jsonEncode(<String, Object>{
      'schema': 'lexiquest.assessment-form.v1',
      'instrumentId': instrumentId,
      'instrumentVersion': instrumentVersion,
      'formId': formId,
      'formVersion': formVersion,
      'formContentRevision': formContentRevision,
      'items': items
          .map(
            (item) => <String, Object>{
              'itemId': item.itemId,
              'prompt': item.prompt,
              'wordId': item.wordId,
              'promptMode': item.promptMode,
              'scoringRuleVersion': item.scoringRuleVersion,
              'responses':
                  (item.responses.entries.toList()
                        ..sort((left, right) => left.key.compareTo(right.key)))
                      .map(
                        (entry) => <String, Object>{
                          'input': entry.key,
                          'responseCode': entry.value.responseCode,
                          'isCorrect': entry.value.isCorrect,
                        },
                      )
                      .toList(growable: false),
            },
          )
          .toList(growable: false),
    }),
  );

  AssessmentItemDefinition item(String itemId) {
    _validateIdentifier(itemId, 'itemId');
    final matches = items.where((item) => item.itemId == itemId).toList();
    if (matches.length != 1) {
      throw ArgumentError.value(
        itemId,
        'itemId',
        'must identify exactly one item in the pinned assessment form',
      );
    }
    return matches.single;
  }
}

final class AssessmentInstrumentCatalog {
  AssessmentInstrumentCatalog({
    required List<AssessmentInstrumentDefinition> entries,
  }) : _entries = List<AssessmentInstrumentDefinition>.unmodifiable(entries);

  final List<AssessmentInstrumentDefinition> _entries;

  AssessmentInstrumentDefinition lookup({
    required String instrumentId,
    required String instrumentVersion,
    required String formId,
    required String formVersion,
  }) {
    _validateIdentifier(instrumentId, 'instrumentId');
    _validateIdentifier(instrumentVersion, 'instrumentVersion');
    _validateIdentifier(formId, 'formId');
    _validateIdentifier(formVersion, 'formVersion');

    final matches = _entries
        .where(
          (entry) =>
              entry.instrumentId == instrumentId &&
              entry.instrumentVersion == instrumentVersion &&
              entry.formId == formId &&
              entry.formVersion == formVersion,
        )
        .toList(growable: false);
    if (matches.length != 1) {
      throw const AssessmentCatalogException(
        'Assessment catalog identity is missing or ambiguous.',
      );
    }
    final definition = matches.single;
    _validateDefinition(definition);
    return definition;
  }
}

final class AssessmentCatalogException implements Exception {
  const AssessmentCatalogException(this.message);

  final String message;

  @override
  String toString() => 'AssessmentCatalogException($message)';
}

const int _maxIdentifierRunes = 256;
const int _maxControlledResponses = 64;
const int _maxPackagedBytes = 1024 * 1024;
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _responseCodePattern = RegExp(r'^[a-z0-9][a-z0-9._:-]*$');

void _validateDefinition(AssessmentInstrumentDefinition definition) {
  for (final entry in <String, String>{
    'instrumentId': definition.instrumentId,
    'instrumentVersion': definition.instrumentVersion,
    'formId': definition.formId,
    'formVersion': definition.formVersion,
    'protocolId': definition.protocolId,
    'experimentId': definition.experimentId,
    'contentRevision': definition.contentRevision,
  }.entries) {
    _validateIdentifier(entry.value, entry.key);
  }
  if (definition.experimentVersion <= 0) {
    throw const AssessmentCatalogException(
      'experimentVersion must be positive.',
    );
  }
  if (definition.formContentRevision <= 0) {
    throw const AssessmentCatalogException(
      'formContentRevision must be positive.',
    );
  }
  if (definition.sourceState != AssessmentCatalogSourceState.approved ||
      definition.reviewState != AssessmentCatalogReviewState.approved) {
    throw const AssessmentCatalogException(
      'Assessment catalog entry is not Approved.',
    );
  }
  _validatePackagedBytes(
    definition.instrumentBytes,
    definition.instrumentChecksumSha256,
    'instrument',
  );
  _validatePackagedBytes(
    definition.formBytes,
    definition.formChecksumSha256,
    'form',
  );
  if (definition.items.isEmpty) {
    throw const AssessmentCatalogException(
      'Assessment form must contain at least one item.',
    );
  }
  final itemIds = <String>{};
  for (final item in definition.items) {
    for (final entry in <String, String>{
      'itemId': item.itemId,
      'prompt': item.prompt,
      'wordId': item.wordId,
      'promptMode': item.promptMode,
      'scoringRuleVersion': item.scoringRuleVersion,
    }.entries) {
      _validateIdentifier(entry.value, entry.key);
    }
    if (!itemIds.add(item.itemId)) {
      throw const AssessmentCatalogException(
        'Assessment item identity is duplicated.',
      );
    }
    if (item.responses.isEmpty ||
        item.responses.length > _maxControlledResponses) {
      throw const AssessmentCatalogException(
        'Assessment response map is empty or unbounded.',
      );
    }
    final responseSemantics = <String, bool>{};
    for (final response in item.responses.entries) {
      _validateIdentifier(response.key, 'controlledResponse');
      _validateIdentifier(response.value.responseCode, 'responseCode');
      if (!_responseCodePattern.hasMatch(response.value.responseCode)) {
        throw const AssessmentCatalogException(
          'Assessment response code is malformed.',
        );
      }
      final existing = responseSemantics[response.value.responseCode];
      if (existing != null && existing != response.value.isCorrect) {
        throw const AssessmentCatalogException(
          'Assessment response code has ambiguous correctness semantics.',
        );
      }
      responseSemantics[response.value.responseCode] = response.value.isCorrect;
    }
  }
  final canonicalFormBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
    instrumentId: definition.instrumentId,
    instrumentVersion: definition.instrumentVersion,
    formId: definition.formId,
    formVersion: definition.formVersion,
    formContentRevision: definition.formContentRevision,
    items: definition.items,
  );
  if (!_sameBytes(definition.formBytes, canonicalFormBytes)) {
    throw const AssessmentCatalogException(
      'Assessment form bytes do not bind the catalog semantics.',
    );
  }
}

Future<void> requireVerifiedAssessmentForm({
  required AssessmentInstrumentDefinition definition,
  required ContentManifestRepository? manifests,
}) async {
  if (manifests == null) {
    throw StateError('Verified assessment-form content is unavailable.');
  }
  final identity = ContentIdentity(
    type: ContentType.assessmentForm,
    id: definition.formId,
    revision: definition.formContentRevision,
  );
  final verified = await manifests.requireVerified(identity);
  final manifest = verified.manifest;
  if (manifest.identity != identity ||
      manifest.checksumSha256 != definition.formChecksumSha256 ||
      manifest.byteLength != definition.formBytes.length ||
      verified.bytes.length != definition.formBytes.length) {
    throw StateError('Verified assessment-form metadata is incompatible.');
  }
  for (var index = 0; index < definition.formBytes.length; index++) {
    if (verified.bytes[index] != definition.formBytes[index]) {
      throw StateError('Verified assessment-form bytes are incompatible.');
    }
  }
}

void _validatePackagedBytes(List<int> bytes, String checksum, String name) {
  if (bytes.isEmpty || bytes.length > _maxPackagedBytes) {
    throw AssessmentCatalogException('$name bytes are empty or unbounded.');
  }
  if (!_sha256Pattern.hasMatch(checksum) ||
      sha256.convert(bytes).toString() != checksum) {
    throw AssessmentCatalogException('$name SHA-256 does not match bytes.');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _validateIdentifier(String value, String name) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > _maxIdentifierRunes) {
    throw AssessmentCatalogException('Invalid $name.');
  }
}
