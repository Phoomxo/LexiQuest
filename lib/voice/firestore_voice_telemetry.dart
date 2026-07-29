import 'package:cloud_firestore/cloud_firestore.dart';
import 'voice_telemetry.dart';

typedef FirestoreDocWriter = Future<void> Function(Map<String, dynamic> data);

/// Production Firestore sink for writing privacy-safe telemetry events.
///
/// Ensures any Firestore connectivity or permission errors are swallowed
/// so telemetry failures never disrupt audio playback or user experience.
final class FirestoreVoiceTelemetrySink implements VoiceTelemetrySink {
  final FirestoreDocWriter? writer;

  FirestoreVoiceTelemetrySink({this.writer});

  @override
  Future<void> record(VoiceTelemetryEvent event) async {
    try {
      final data = event.toMap();
      if (writer != null) {
        await writer!(data);
      } else {
        await FirebaseFirestore.instance
            .collection('voice_telemetry_events')
            .add(data);
      }
    } catch (_) {
      // Telemetry write failure must never block audio or application flow.
    }
  }
}
