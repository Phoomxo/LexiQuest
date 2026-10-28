import 'dart:convert';

import 'package:crypto/crypto.dart';

final class ExperimentAssignment {
  const ExperimentAssignment({
    required this.id,
    required this.ownerId,
    required this.experimentId,
    required this.experimentVersion,
    required this.cohort,
    required this.protocolVersion,
    required this.assignedAtUtc,
  });

  final String id;
  final String ownerId;
  final String experimentId;
  final int experimentVersion;
  final String cohort;
  final String protocolVersion;
  final DateTime assignedAtUtc;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExperimentAssignment &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.experimentId == experimentId &&
          other.experimentVersion == experimentVersion &&
          other.cohort == cohort &&
          other.protocolVersion == protocolVersion &&
          other.assignedAtUtc == assignedAtUtc;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    experimentId,
    experimentVersion,
    cohort,
    protocolVersion,
    assignedAtUtc,
  );
}

final class ExperimentAssignmentConflict implements Exception {
  const ExperimentAssignmentConflict({
    required this.ownerId,
    required this.experimentId,
    required this.experimentVersion,
  });

  final String ownerId;
  final String experimentId;
  final int experimentVersion;
}

String experimentAssignmentId({
  required String ownerId,
  required String experimentId,
  required int experimentVersion,
}) =>
    'experiment-assignment:${sha256.convert(utf8.encode(jsonEncode([ownerId, experimentId, experimentVersion])))}';
