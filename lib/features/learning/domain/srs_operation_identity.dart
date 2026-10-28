import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class SrsOperationIdentity {
  static final RegExp _currentPattern = RegExp(
    r'^srsState:v2:[0-9a-f]{64}:r([1-9][0-9]*)$',
  );
  static final RegExp _legacyPattern = RegExp(
    r'^srsState:(?!v2:).+:([1-9][0-9]*)$',
  );

  static String create({
    required String ownerId,
    required String wordId,
    required String answerAttemptId,
    required int revision,
  }) {
    final canonicalOwnerId = ownerId.trim();
    final canonicalWordId = wordId.trim();
    final canonicalAttemptId = answerAttemptId.trim();
    _requireId(canonicalOwnerId, ownerId, 'ownerId');
    _requireId(canonicalWordId, wordId, 'wordId');
    _requireId(canonicalAttemptId, answerAttemptId, 'answerAttemptId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    final digest = sha256.convert(
      utf8.encode(
        '$canonicalOwnerId\u0000$canonicalWordId\u0000$canonicalAttemptId',
      ),
    );
    return 'srsState:v2:$digest:r$revision';
  }

  static int? tryParseRevision(String operationId) {
    final currentMatch = _currentPattern.firstMatch(operationId);
    final legacyMatch = _legacyPattern.firstMatch(operationId);
    final segment = (currentMatch ?? legacyMatch)?.group(1);
    return segment == null ? null : int.parse(segment);
  }

  static void _requireId(String canonical, String original, String name) {
    if (canonical.isEmpty) {
      throw ArgumentError.value(original, name, 'must not be blank');
    }
  }
}
