import 'motivation_instrument.dart';

enum MotivationMeasurementRunState {
  started,
  completed,
  skipped,
  abandoned,
  withdrawn,
}

enum ResearchCaptureReason {
  eligible,
  noPermit,
  invalidPermit,
  expiredPermit,
  revokedPermit,
  noActiveRun,
  withdrawn,
  versionConflict,
  ownerConflict,
  outsideWindow,
  incomplete,
  identityConflict,
  sessionUnavailable,
}

final class ResearchCaptureDenied implements Exception {
  const ResearchCaptureDenied(this.reason);
  final ResearchCaptureReason reason;
  @override
  String toString() => 'Research capture denied: ${reason.name}';
}

final class MotivationMeasurementStart {
  const MotivationMeasurementStart({
    required this.ownerId,
    required this.permitId,
  });
  final String ownerId;
  final String permitId;
}

final class MotivationResponse {
  const MotivationResponse({
    required this.ownerId,
    required this.runId,
    required this.itemId,
    required this.responseCode,
  });
  final String ownerId;
  final String runId;
  final String itemId;
  final String responseCode;
}

final class MotivationMeasurementClose {
  const MotivationMeasurementClose({
    required this.ownerId,
    required this.runId,
    required this.state,
  });
  final String ownerId;
  final String runId;
  final MotivationMeasurementRunState state;
}

final class RecordedMotivationResponse {
  const RecordedMotivationResponse({
    required this.itemId,
    required this.responseCode,
    required this.ordinalValue,
    required this.answeredAtUtc,
  });
  final String itemId;
  final String responseCode;
  final int? ordinalValue;
  final DateTime answeredAtUtc;
}

final class MotivationMeasurementRun {
  MotivationMeasurementRun({
    required this.id,
    required this.ownerId,
    required this.permitId,
    required this.assignmentId,
    required this.instrument,
    required this.state,
    required this.startedAtUtc,
    this.closedAtUtc,
    required List<RecordedMotivationResponse> responses,
    this.firstExposureAtUtc,
    this.indexCompletionAtUtc,
  }) : responses = List.unmodifiable(responses);
  final String id;
  final String ownerId;
  final String permitId;
  final String assignmentId;
  final MotivationInstrument instrument;
  final MotivationMeasurementRunState state;
  final DateTime startedAtUtc;
  final DateTime? closedAtUtc;
  final List<RecordedMotivationResponse> responses;
  final DateTime? firstExposureAtUtc;
  final DateTime? indexCompletionAtUtc;
  double? score(MotivationTimepoint point) => instrument.normalizedScore(
    point,
    {for (final response in responses) response.itemId: response.responseCode},
  );
  bool get primaryAnalysisEligible {
    final exposure = firstExposureAtUtc;
    final completion = indexCompletionAtUtc;
    if (state != MotivationMeasurementRunState.completed ||
        exposure == null ||
        completion == null ||
        score(MotivationTimepoint.baseline) == null ||
        score(MotivationTimepoint.post) == null) {
      return false;
    }
    return responses.every((response) {
      final baseline =
          instrument.item(response.itemId).timepoint ==
          MotivationTimepoint.baseline;
      return baseline
          ? !response.answeredAtUtc.isAfter(exposure) &&
                !response.answeredAtUtc.isBefore(
                  exposure.subtract(const Duration(hours: 24)),
                )
          : !response.answeredAtUtc.isBefore(completion) &&
                !response.answeredAtUtc.isAfter(
                  completion.add(const Duration(minutes: 30)),
                );
    });
  }
}
