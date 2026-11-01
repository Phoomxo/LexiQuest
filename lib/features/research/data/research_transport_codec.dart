part of 'http_research_authority_gateway.dart';

Map<String, Object?> _scopeJson(ResearchAuthorityScope scope) => {
  'binding': {
    'ownerId': scope.binding.ownerId,
    'authSubjectId': scope.binding.authSubjectId,
    'generation': scope.binding.generation,
  },
  'requirements': _requirementsJson(scope.requirements),
  'protocolVersion': scope.protocolVersion,
  'consentVersion': scope.consentVersion,
};

Map<String, Object?> _requirementsJson(ResearchPermitRequirements value) => {
  'supportedFormatVersion': value.supportedFormatVersion,
  'trustedIssuerId': value.trustedIssuerId,
  'trustedIssuerKeyId': value.trustedIssuerKeyId,
  'signatureAlgorithm': value.signatureAlgorithm,
  'assignmentId': value.assignmentId,
  'assignmentRevision': value.assignmentRevision,
  'protocolId': value.protocolId,
  'protocolRevision': value.protocolRevision,
  'instrumentId': value.instrumentId,
  'instrumentRevision': value.instrumentRevision,
};

ResearchAuthorityScope _scope(Object? raw) {
  final value = _map(raw);
  _keys(value, const {
    'binding',
    'requirements',
    'protocolVersion',
    'consentVersion',
  });
  final binding = _map(value['binding']);
  _keys(binding, const {'ownerId', 'authSubjectId', 'generation'});
  return ResearchAuthorityScope(
    binding: ResearchAuthorityBinding(
      ownerId: _code(binding['ownerId']),
      authSubjectId: _code(binding['authSubjectId']),
      generation: _integer(binding['generation'], minimum: 0),
    ),
    requirements: _requirements(value['requirements']),
    protocolVersion: _code(value['protocolVersion']),
    consentVersion: _integer(value['consentVersion']),
  );
}

ResearchPermitRequirements _requirements(Object? raw) {
  final value = _map(raw);
  _keys(value, const {
    'supportedFormatVersion',
    'trustedIssuerId',
    'trustedIssuerKeyId',
    'signatureAlgorithm',
    'assignmentId',
    'assignmentRevision',
    'protocolId',
    'protocolRevision',
    'instrumentId',
    'instrumentRevision',
  });
  return ResearchPermitRequirements(
    supportedFormatVersion: _integer(value['supportedFormatVersion']),
    trustedIssuerId: _code(value['trustedIssuerId']),
    trustedIssuerKeyId: _code(value['trustedIssuerKeyId']),
    signatureAlgorithm: _code(value['signatureAlgorithm']),
    assignmentId: _code(value['assignmentId']),
    assignmentRevision: _integer(value['assignmentRevision']),
    protocolId: _code(value['protocolId']),
    protocolRevision: _integer(value['protocolRevision']),
    instrumentId: _code(value['instrumentId']),
    instrumentRevision: _integer(value['instrumentRevision']),
  );
}

ResearchAuthorityReceipt _receipt(Object? raw) {
  final value = _map(raw);
  _keys(value, const {
    'ownerId',
    'receiptId',
    'kind',
    'revision',
    'active',
    'issuedAtUtc',
    'expiresAtUtc',
    'consentVersion',
    'decidedAtUtc',
  });
  final name = _code(value['kind']);
  final kind = ResearchReceiptKind.values
      .where((kind) => kind.name == name)
      .single;
  final issuedAt = _utc(value['issuedAtUtc']);
  final expiresAt = _utc(value['expiresAtUtc']);
  final version = value['consentVersion'] == null
      ? null
      : _integer(value['consentVersion']);
  final decision = value['decidedAtUtc'] == null
      ? null
      : _utc(value['decidedAtUtc']);
  if (!expiresAt.isAfter(issuedAt) ||
      (kind == ResearchReceiptKind.consent &&
          (version == null || decision == null)) ||
      (kind != ResearchReceiptKind.consent &&
          (version != null || decision != null))) {
    _invalid();
  }
  return ResearchAuthorityReceipt(
    ownerId: _code(value['ownerId']),
    receiptId: _code(value['receiptId']),
    kind: kind,
    revision: _integer(value['revision']),
    active: _boolean(value['active']),
    issuedAtUtc: issuedAt,
    expiresAtUtc: expiresAt,
    consentVersion: version,
    decidedAtUtc: decision,
  );
}

List<int> _documentBytes(Object? raw) {
  final text = _text(raw, ((16384 + 2) ~/ 3) * 4);
  final bytes = base64.decode(text);
  if (bytes.length > 16384 || base64.encode(bytes) != text) _invalid();
  return bytes;
}

Uri _origin(Uri value) {
  if (value.scheme != 'https' ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw ArgumentError(
      'Research requires an explicitly configured HTTPS origin',
    );
  }
  return value;
}

T _decode<T>(T Function() decode) {
  try {
    return decode();
  } on ResearchTransportException {
    rethrow;
  } on Object {
    _invalid();
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) _invalid();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    _invalid();
  }
}

void _version(Map<String, dynamic> value) {
  if (value['schemaVersion'] != 1 || value['schemaVersion'] is! int) _invalid();
}

List<dynamic> _list(Object? value, int maximum) {
  if (value is! List || value.length > maximum) _invalid();
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.trim() != value ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    _invalid();
  }
  return value;
}

String _code(Object? value) {
  final result = _text(value, 128);
  if (!RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(result)) _invalid();
  return result;
}

String _hash(Object? value) {
  final result = _text(value, 64);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) _invalid();
  return result;
}

int _integer(Object? value, {int minimum = 1, int maximum = 9007199254740991}) {
  if (value is! int || value < minimum || value > maximum) _invalid();
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) _invalid();
  return value;
}

DateTime _utc(Object? value) {
  final text = _text(value, 24);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  ).hasMatch(text)) {
    _invalid();
  }
  final date = DateTime.tryParse(text);
  if (date == null ||
      !date.isUtc ||
      date.millisecondsSinceEpoch < 0 ||
      date.toIso8601String() != text) {
    _invalid();
  }
  return date;
}

Never _invalid() => throw const ResearchTransportException(
  ResearchTransportFailureCode.invalidResponse,
);
