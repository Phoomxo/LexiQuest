import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';

// Synthetic bytes and approval labels exercise integrity, never study approval.
void main() {
  test('explicit mapping binds numeric revisions without parsing versions', () {
    final definition = _definition();
    final mapping = _mapping(definition);
    mapping.requireMatches(scope: _scope(), definition: definition);
    expect(mapping.instrumentRevision, 41);
    expect(mapping.instrumentVersion, '1');
    expect(mapping.formContentRevision, 1);
    for (final changes in [
      {'protocolId': 'other-protocol'},
      {'protocolVersion': 'other-version'},
      {'protocolRevision': 31},
      {'instrumentId': 'other-instrument'},
      {'instrumentRevision': 42},
    ]) {
      expect(
        () => mapping.requireMatches(
          scope: _scope(changes),
          definition: definition,
        ),
        throwsStateError,
      );
    }
  });
  test('explicit mapping rejects rotated catalog metadata and byte pins', () {
    final definition = _definition();
    final mapping = _mapping(definition);
    for (final changed in [
      _definition(formVersion: 'rotated'),
      _definition(formContentRevision: 2),
      _definition(experimentVersion: 2),
      _definition(instrumentBytes: utf8.encode('rotated instrument bytes')),
      _definition(items: [_item(scoringRuleVersion: 'rotated-score')]),
    ]) {
      expect(
        () => mapping.requireMatches(scope: _scope(), definition: changed),
        throwsStateError,
      );
    }
  });
  test('explicit mapping validates every supplied canonical pin', () {
    final definition = _definition();
    for (final key in [
      'protocolId',
      'protocolVersion',
      'instrumentId',
      'instrumentVersion',
      'formId',
      'formVersion',
      'experimentId',
      'contentRevision',
    ]) {
      for (final value in ['', ' supplied ', 'x' * 257]) {
        expect(() => _mapping(definition, {key: value}), throwsArgumentError);
      }
    }
    for (final key in [
      'protocolRevision',
      'instrumentRevision',
      'formContentRevision',
      'experimentVersion',
    ]) {
      expect(() => _mapping(definition, {key: 0}), throwsArgumentError);
      expect(() => _mapping(definition, {key: -1}), throwsArgumentError);
    }
    for (final key in ['instrumentChecksumSha256', 'formChecksumSha256']) {
      expect(() => _mapping(definition, {key: 'A' * 64}), throwsArgumentError);
      expect(() => _mapping(definition, {key: 'a' * 63}), throwsArgumentError);
    }
  });
  test(
    'catalog returns one pinned synthetic definition with controlled scoring',
    () {
      final definition = _definition();
      final catalog = AssessmentInstrumentCatalog(entries: [definition]);
      expect(_lookup(catalog), same(definition));
      expect(
        definition.item('synthetic-item').responses['synthetic yes']!.isCorrect,
        isTrue,
      );
      expect(
        definition
            .item('synthetic-item')
            .responses['synthetic no']!
            .responseCode,
        'incorrect',
      );
      expect(() => definition.item('unknown'), throwsArgumentError);
    },
  );
  test(
    'canonical form bytes bind versions, ordered items and sorted responses',
    () {
      final original = _definition();
      final reversed = _definition(
        items: [
          _item(
            responses: {
              'synthetic no': const AssessmentControlledResponse(
                responseCode: 'incorrect',
                isCorrect: false,
              ),
              'synthetic yes': const AssessmentControlledResponse(
                responseCode: 'correct',
                isCorrect: true,
              ),
            },
          ),
        ],
      );
      expect(reversed.formBytes, original.formBytes);
      for (final changed in [
        _definition(formVersion: '2'),
        _definition(formContentRevision: 2),
        _definition(items: [_item(scoringRuleVersion: 'synthetic-score-2')]),
      ]) {
        expect(changed.formBytes, isNot(original.formBytes));
        expect(changed.formChecksumSha256, isNot(original.formChecksumSha256));
      }
    },
  );
  test('catalog deeply copies every caller-owned collection', () {
    final instrumentBytes = utf8.encode('synthetic instrument bytes');
    final responses = <String, AssessmentControlledResponse>{
      'synthetic yes': const AssessmentControlledResponse(
        responseCode: 'correct',
        isCorrect: true,
      ),
      'synthetic no': const AssessmentControlledResponse(
        responseCode: 'incorrect',
        isCorrect: false,
      ),
    };
    final items = [_item(responses: responses)];
    final definition = _definition(
      items: items,
      instrumentBytes: instrumentBytes,
    );
    final entries = [definition];
    final catalog = AssessmentInstrumentCatalog(entries: entries);
    instrumentBytes[0] ^= 1;
    responses.clear();
    items.clear();
    entries.clear();
    expect(_lookup(catalog).items.single.responses, hasLength(2));
    expect(() => definition.instrumentBytes.clear(), throwsUnsupportedError);
    expect(() => definition.formBytes.clear(), throwsUnsupportedError);
    expect(() => definition.items.clear(), throwsUnsupportedError);
    expect(
      () => definition.items.single.responses.clear(),
      throwsUnsupportedError,
    );
  });
  test('missing and ambiguous identities fail closed', () {
    expect(
      () => _lookup(AssessmentInstrumentCatalog(entries: [])),
      _catalogFailure,
    );
    final definition = _definition();
    expect(
      () => _lookup(
        AssessmentInstrumentCatalog(entries: [definition, definition]),
      ),
      _catalogFailure,
    );
    expect(
      () => AssessmentInstrumentCatalog(entries: [definition]).lookup(
        instrumentId: 'synthetic-instrument',
        instrumentVersion: '2',
        formId: 'synthetic-form',
        formVersion: '1',
      ),
      _catalogFailure,
    );
  });
  for (final state in AssessmentCatalogReviewState.values.where(
    (state) => state != AssessmentCatalogReviewState.approved,
  )) {
    test('unapproved review state $state cannot provide a form', () {
      expect(() => _checked(_definition(reviewState: state)), _catalogFailure);
    });
  }
  test('unsupported source and invalid versions cannot provide a form', () {
    expect(
      () => _checked(
        _definition(sourceState: AssessmentCatalogSourceState.unsupported),
      ),
      _catalogFailure,
    );
    expect(
      () => _checked(_definition(formContentRevision: 0)),
      _catalogFailure,
    );
    expect(() => _checked(_definition(experimentVersion: 0)), _catalogFailure);
    expect(() => _checked(_definition(formVersion: ' 1 ')), _catalogFailure);
  });
  test('both instrument and form bytes require complete matching SHA256', () {
    expect(() => _checked(_definition(instrumentBytes: [])), _catalogFailure);
    expect(() => _checked(_definition(formBytes: [])), _catalogFailure);
    expect(
      () => _checked(_definition(instrumentChecksum: 'a' * 64)),
      _catalogFailure,
    );
    expect(
      () => _checked(_definition(formChecksum: 'b' * 64)),
      _catalogFailure,
    );
    expect(
      () => _checked(_definition(instrumentChecksum: 'A' * 64)),
      _catalogFailure,
    );
    expect(
      () => _checked(
        _definition(instrumentBytes: List.filled(1024 * 1024 + 1, 1)),
      ),
      _catalogFailure,
    );
    for (final bytes in [
      [-1],
      [256],
    ]) {
      expect(
        () => _checked(
          _definition(instrumentBytes: bytes, instrumentChecksum: 'a' * 64),
        ),
        _catalogFailure,
      );
    }
  });
  test(
    'a matching hash cannot legitimize bytes detached from item semantics',
    () {
      final bytes = utf8.encode('synthetic detached form');
      expect(() => _checked(_definition(formBytes: bytes)), _catalogFailure);
    },
  );
  test(
    'empty forms, duplicate items and malformed controlled scoring are rejected',
    () {
      final invalidItems = <List<AssessmentItemDefinition>>[
        [],
        [_item(), _item()],
        [_item(itemId: ' untrimmed ')],
        [_item(responses: {})],
        [
          _item(
            responses: {
              'only one': const AssessmentControlledResponse(
                responseCode: 'correct',
                isCorrect: true,
              ),
            },
          ),
        ],
        [
          _item(
            responses: {
              'yes': const AssessmentControlledResponse(
                responseCode: 'Wrong Code',
                isCorrect: true,
              ),
              'no': const AssessmentControlledResponse(
                responseCode: 'incorrect',
                isCorrect: false,
              ),
            },
          ),
        ],
        [
          _item(
            responses: {
              'yes': const AssessmentControlledResponse(
                responseCode: 'same',
                isCorrect: true,
              ),
              'no': const AssessmentControlledResponse(
                responseCode: 'same',
                isCorrect: false,
              ),
            },
          ),
        ],
        [
          _item(
            responses: {
              for (var index = 0; index < 65; index++)
                'synthetic-$index': AssessmentControlledResponse(
                  responseCode: 'code-$index',
                  isCorrect: index == 0,
                ),
            },
          ),
        ],
      ];
      for (final items in invalidItems) {
        expect(() => _checked(_definition(items: items)), _catalogFailure);
      }
    },
  );
  test(
    'verified form requires an explicitly supplied content authority',
    () async {
      await expectLater(
        requireVerifiedAssessmentForm(
          definition: _definition(),
          contentAuthority: null,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'verified form requests exact content identity and validates returned bytes',
    () async {
      final definition = _definition();
      final authority = _ContentAuthority(
        (identity) async => AssessmentVerifiedFormContent(
          identity: identity,
          checksumSha256: definition.formChecksumSha256,
          bytes: definition.formBytes,
        ),
      );
      await requireVerifiedAssessmentForm(
        definition: definition,
        contentAuthority: authority,
      );
      expect(authority.requests, [
        AssessmentFormContentIdentity(
          formId: definition.formId,
          revision: definition.formContentRevision,
        ),
      ]);
    },
  );
  test(
    'authority errors propagate without accepting a catalog-only approval',
    () async {
      final authority = _ContentAuthority((_) async {
        throw StateError('synthetic content authority unavailable');
      });
      await expectLater(
        requireVerifiedAssessmentForm(
          definition: _definition(),
          contentAuthority: authority,
        ),
        throwsStateError,
      );
      expect(authority.requests, hasLength(1));
    },
  );
  test(
    'returned identity, hash, length and bytes must bind the same form',
    () async {
      final definition = _definition();
      final expectedIdentity = AssessmentFormContentIdentity(
        formId: definition.formId,
        revision: definition.formContentRevision,
      );
      final differentBytes = [...definition.formBytes];
      differentBytes[0] ^= 1;
      for (final content in [
        AssessmentVerifiedFormContent(
          identity: AssessmentFormContentIdentity(
            formId: 'synthetic-other',
            revision: 1,
          ),
          checksumSha256: definition.formChecksumSha256,
          bytes: definition.formBytes,
        ),
        AssessmentVerifiedFormContent(
          identity: AssessmentFormContentIdentity(
            formId: definition.formId,
            revision: 2,
          ),
          checksumSha256: definition.formChecksumSha256,
          bytes: definition.formBytes,
        ),
        AssessmentVerifiedFormContent(
          identity: expectedIdentity,
          checksumSha256: 'a' * 64,
          bytes: definition.formBytes,
        ),
        AssessmentVerifiedFormContent(
          identity: expectedIdentity,
          checksumSha256: definition.formChecksumSha256,
          bytes: definition.formBytes.sublist(1),
        ),
        AssessmentVerifiedFormContent(
          identity: expectedIdentity,
          checksumSha256: sha256.convert(differentBytes).toString(),
          bytes: differentBytes,
        ),
      ]) {
        final authority = _ContentAuthority((_) async => content);
        await expectLater(
          requireVerifiedAssessmentForm(
            definition: definition,
            contentAuthority: authority,
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'verified content snapshots cannot mutate while authority is awaited',
    () async {
      final definition = _definition();
      final bytes = [...definition.formBytes];
      final content = AssessmentVerifiedFormContent(
        identity: AssessmentFormContentIdentity(
          formId: definition.formId,
          revision: 1,
        ),
        checksumSha256: definition.formChecksumSha256,
        bytes: bytes,
      );
      bytes.clear();
      expect(content.bytes, definition.formBytes);
      expect(() => content.bytes.clear(), throwsUnsupportedError);
      await requireVerifiedAssessmentForm(
        definition: definition,
        contentAuthority: _ContentAuthority((_) async => content),
      );
    },
  );
  test(
    'content identities require canonical bounded IDs and positive revisions',
    () {
      for (final id in ['', ' synthetic ', 'x' * 257]) {
        expect(
          () => AssessmentFormContentIdentity(formId: id, revision: 1),
          throwsArgumentError,
        );
      }
      expect(
        () => AssessmentFormContentIdentity(
          formId: 'synthetic-form',
          revision: 0,
        ),
        throwsArgumentError,
      );
      final first = AssessmentFormContentIdentity(
        formId: 'synthetic-form',
        revision: 1,
      );
      final retry = AssessmentFormContentIdentity(
        formId: 'synthetic-form',
        revision: 1,
      );
      expect(first, retry);
      expect(first.hashCode, retry.hashCode);
    },
  );
}

Matcher get _catalogFailure => throwsA(isA<AssessmentCatalogException>());

AssessmentInstrumentDefinition _lookup(AssessmentInstrumentCatalog catalog) =>
    catalog.lookup(
      instrumentId: 'synthetic-instrument',
      instrumentVersion: '1',
      formId: 'synthetic-form',
      formVersion: '1',
    );

AssessmentInstrumentDefinition _checked(
  AssessmentInstrumentDefinition definition,
) => AssessmentInstrumentCatalog(entries: [definition]).lookup(
  instrumentId: definition.instrumentId,
  instrumentVersion: definition.instrumentVersion,
  formId: definition.formId,
  formVersion: definition.formVersion,
);

AssessmentItemDefinition _item({
  String itemId = 'synthetic-item',
  String scoringRuleVersion = 'synthetic-score-1',
  Map<String, AssessmentControlledResponse>? responses,
}) => AssessmentItemDefinition(
  itemId: itemId,
  prompt: 'Synthetic item',
  wordId: 'synthetic-word',
  promptMode: 'meaningChoice',
  scoringRuleVersion: scoringRuleVersion,
  responses:
      responses ??
      const {
        'synthetic yes': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'synthetic no': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
);

AssessmentInstrumentDefinition _definition({
  String formVersion = '1',
  int formContentRevision = 1,
  int experimentVersion = 1,
  AssessmentCatalogSourceState sourceState =
      AssessmentCatalogSourceState.approved,
  AssessmentCatalogReviewState reviewState =
      AssessmentCatalogReviewState.approved,
  List<AssessmentItemDefinition>? items,
  List<int>? instrumentBytes,
  List<int>? formBytes,
  String? instrumentChecksum,
  String? formChecksum,
}) {
  final actualItems = items ?? [_item()];
  final actualInstrument =
      instrumentBytes ?? utf8.encode('synthetic instrument bytes');
  final actualForm =
      formBytes ??
      AssessmentInstrumentDefinition.canonicalFormBytes(
        instrumentId: 'synthetic-instrument',
        instrumentVersion: '1',
        formId: 'synthetic-form',
        formVersion: formVersion,
        formContentRevision: formContentRevision,
        items: actualItems,
      );
  return AssessmentInstrumentDefinition(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: '1',
    formId: 'synthetic-form',
    formVersion: formVersion,
    formContentRevision: formContentRevision,
    sourceState: sourceState,
    reviewState: reviewState,
    protocolId: 'synthetic-protocol',
    experimentId: 'synthetic-experiment',
    experimentVersion: experimentVersion,
    contentRevision: 'synthetic-content',
    instrumentBytes: actualInstrument,
    formBytes: actualForm,
    instrumentChecksumSha256:
        instrumentChecksum ?? sha256.convert(actualInstrument).toString(),
    formChecksumSha256: formChecksum ?? sha256.convert(actualForm).toString(),
    items: actualItems,
  );
}

final class _ContentAuthority implements AssessmentFormContentAuthority {
  _ContentAuthority(this.read);
  final Future<AssessmentVerifiedFormContent> Function(
    AssessmentFormContentIdentity,
  )
  read;
  final requests = <AssessmentFormContentIdentity>[];

  @override
  Future<AssessmentVerifiedFormContent> requireVerified(
    AssessmentFormContentIdentity identity,
  ) {
    requests.add(identity);
    return read(identity);
  }
}

AssessmentAuthorityMapping _mapping(
  AssessmentInstrumentDefinition definition, [
  Map<String, Object> changes = const {},
]) {
  final pins = <String, Object>{
    'protocolId': definition.protocolId,
    'protocolVersion': 'supplied-version-one',
    'protocolRevision': 30,
    'instrumentId': definition.instrumentId,
    'instrumentRevision': 41,
    'instrumentVersion': definition.instrumentVersion,
    'formId': definition.formId,
    'formVersion': definition.formVersion,
    'formContentRevision': definition.formContentRevision,
    'instrumentChecksumSha256': definition.instrumentChecksumSha256,
    'formChecksumSha256': definition.formChecksumSha256,
    'experimentId': definition.experimentId,
    'experimentVersion': definition.experimentVersion,
    'contentRevision': definition.contentRevision,
    ...changes,
  };
  return AssessmentAuthorityMapping(
    protocolId: pins['protocolId']! as String,
    protocolVersion: pins['protocolVersion']! as String,
    protocolRevision: pins['protocolRevision']! as int,
    instrumentId: pins['instrumentId']! as String,
    instrumentRevision: pins['instrumentRevision']! as int,
    instrumentVersion: pins['instrumentVersion']! as String,
    formId: pins['formId']! as String,
    formVersion: pins['formVersion']! as String,
    formContentRevision: pins['formContentRevision']! as int,
    instrumentChecksumSha256: pins['instrumentChecksumSha256']! as String,
    formChecksumSha256: pins['formChecksumSha256']! as String,
    experimentId: pins['experimentId']! as String,
    experimentVersion: pins['experimentVersion']! as int,
    contentRevision: pins['contentRevision']! as String,
  );
}

ResearchAuthorityScope _scope([Map<String, Object> changes = const {}]) =>
    ResearchAuthorityScope(
      binding: ResearchAuthorityBinding(
        ownerId: 'synthetic-owner',
        authSubjectId: 'synthetic-subject',
        generation: 1,
      ),
      requirements: ResearchPermitRequirements(
        supportedFormatVersion: 1,
        trustedIssuerId: 'synthetic-issuer',
        trustedIssuerKeyId: 'synthetic-key',
        signatureAlgorithm: 'ed25519',
        assignmentId: 'synthetic-assignment',
        assignmentRevision: 1,
        protocolId: changes['protocolId'] as String? ?? 'synthetic-protocol',
        protocolRevision: changes['protocolRevision'] as int? ?? 30,
        instrumentId:
            changes['instrumentId'] as String? ?? 'synthetic-instrument',
        instrumentRevision: changes['instrumentRevision'] as int? ?? 41,
      ),
      protocolVersion:
          changes['protocolVersion'] as String? ?? 'supplied-version-one',
      consentVersion: 4,
    );
