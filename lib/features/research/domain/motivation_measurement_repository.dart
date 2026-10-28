import 'motivation_measurement.dart';

abstract interface class MotivationMeasurementRepository {
  Future<MotivationMeasurementRun> start(MotivationMeasurementStart command);
  Future<MotivationMeasurementRun> record(MotivationResponse response);
  Future<MotivationMeasurementRun> close(MotivationMeasurementClose command);
  Future<MotivationMeasurementRun?> load(String ownerId, String runId);
}
