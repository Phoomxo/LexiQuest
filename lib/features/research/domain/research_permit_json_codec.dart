import 'dart:convert';
import 'dart:typed_data';

import 'research_operation_authorizer.dart';

final class ResearchPermitJsonCodec {
  const ResearchPermitJsonCodec();

  Uint8List encode(ResearchPermit permit) {
    final value = jsonDecode(utf8.decode(permit.signedPayload()));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid permit payload');
    }
    value['signature'] = base64Url.encode(permit.signature).replaceAll('=', '');
    return Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }

  ResearchPermit decode(Uint8List bytes) {
    final text = utf8.decode(bytes);
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> ||
        !_hasExactKeys(value, const [
          'formatVersion',
          'permitId',
          'issuerId',
          'issuerKeyId',
          'signatureAlgorithm',
          'ownerId',
          'operation',
          'assignmentId',
          'assignmentRevision',
          'protocolId',
          'protocolRevision',
          'instrumentId',
          'instrumentRevision',
          'revision',
          'issuedAtUtcMs',
          'expiresAtUtcMs',
          'signature',
        ])) {
      throw const FormatException('Invalid permit schema');
    }

    final signatureText = _string(value, 'signature');
    if (signatureText.contains('=') || signatureText.isEmpty) {
      throw const FormatException('Invalid permit signature encoding');
    }
    late final Uint8List signature;
    try {
      signature = base64Url.decode(base64Url.normalize(signatureText));
    } on FormatException {
      throw const FormatException('Invalid permit signature encoding');
    }
    if (base64Url.encode(signature).replaceAll('=', '') != signatureText) {
      throw const FormatException('Non-canonical permit signature encoding');
    }

    final operationName = _string(value, 'operation');
    final operation = ResearchOperation.values
        .cast<ResearchOperation?>()
        .firstWhere(
          (candidate) => candidate?.wireName == operationName,
          orElse: () => null,
        );
    if (operation == null) throw const FormatException('Invalid operation');

    final permit = ResearchPermit(
      formatVersion: _integer(value, 'formatVersion'),
      permitId: _string(value, 'permitId'),
      issuerId: _string(value, 'issuerId'),
      issuerKeyId: _string(value, 'issuerKeyId'),
      signatureAlgorithm: _string(value, 'signatureAlgorithm'),
      ownerId: _string(value, 'ownerId'),
      operation: operation,
      assignmentId: _string(value, 'assignmentId'),
      assignmentRevision: _integer(value, 'assignmentRevision'),
      protocolId: _string(value, 'protocolId'),
      protocolRevision: _integer(value, 'protocolRevision'),
      instrumentId: _string(value, 'instrumentId'),
      instrumentRevision: _integer(value, 'instrumentRevision'),
      revision: _integer(value, 'revision'),
      issuedAtUtc: _timestamp(value, 'issuedAtUtcMs'),
      expiresAtUtc: _timestamp(value, 'expiresAtUtcMs'),
      signature: signature,
    );
    if (utf8.decode(encode(permit)) != text) {
      throw const FormatException('Non-canonical permit JSON');
    }
    return permit;
  }

  bool _hasExactKeys(Map<String, dynamic> value, List<String> keys) =>
      value.length == keys.length &&
      value.keys.toList().asMap().entries.every(
        (entry) => entry.value == keys[entry.key],
      );

  int _integer(Map<String, dynamic> value, String key) {
    final field = value[key];
    if (field is! int) throw FormatException('$key must be an integer');
    return field;
  }

  DateTime _timestamp(Map<String, dynamic> value, String key) {
    final milliseconds = _integer(value, key);
    const limit = 8640000000000000;
    if (milliseconds < -limit || milliseconds > limit) {
      throw FormatException('$key is outside the supported DateTime range');
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  String _string(Map<String, dynamic> value, String key) {
    final field = value[key];
    if (field is! String || field.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return field;
  }
}
