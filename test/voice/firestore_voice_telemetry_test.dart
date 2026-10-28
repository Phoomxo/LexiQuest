import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/firestore_voice_telemetry.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

class FakeFirestoreWriter {
  final List<Map<String, dynamic>> writtenEvents = [];
  bool shouldThrow = false;

  Future<void> add(Map<String, dynamic> data) async {
    if (shouldThrow) {
      throw Exception('Firestore write failed');
    }
    writtenEvents.add(Map<String, dynamic>.from(data));
  }
}

void main() {
  test(
    'FirestoreVoiceTelemetrySink serializes privacy-safe telemetry event to writer',
    () async {
      final writer = FakeFirestoreWriter();
      final sink = FirestoreVoiceTelemetrySink(writer: writer.add);

      final req = VoiceRequest.create(
        text: 'apple',
        language: 'en',
        voiceId: 'teacher_female',
        speed: 1.0,
        mode: VoiceMode.practice,
        contentId: 'word-1',
        contentType: 'vocabulary',
      );

      final result = const VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: true,
        requestId: 'req-999',
        modelVersion: '0.2.1',
      );

      final event = VoiceTelemetryEvent.succeeded(
        request: req,
        result: result,
        latency: const Duration(milliseconds: 120),
        occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 0, 0),
      );

      await sink.record(event);

      expect(writer.writtenEvents.length, 1);
      final data = writer.writtenEvents.first;
      expect(data['schemaVersion'], 'voice_telemetry_v1');
      expect(data['outcome'], 'succeeded');
      expect(data['contentId'], 'word-1');
      expect(data['contentType'], 'vocabulary');
      expect(data['cacheHit'], true);
      expect(data['latencyMs'], 120);
      expect(data.containsKey('spokenText'), false);
      expect(data.containsKey('text'), false);
    },
  );

  test(
    'FirestoreVoiceTelemetrySink gracefully catches and isolates write errors',
    () async {
      final writer = FakeFirestoreWriter()..shouldThrow = true;
      final sink = FirestoreVoiceTelemetrySink(writer: writer.add);

      final req = VoiceRequest.create(
        text: 'cat',
        language: 'en',
        voiceId: 'teacher_female',
        speed: 1.0,
        mode: VoiceMode.practice,
        contentId: 'word-2',
        contentType: 'vocabulary',
      );

      final event = VoiceTelemetryEvent.failed(
        request: req,
        requestedEngine: VoiceEngine.omniVoice,
        failure: const VoiceFailure(
          category: VoiceFailureCategory.network,
          message: 'Timeout connecting to backend',
        ),
        latency: const Duration(milliseconds: 5000),
        occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 0, 0),
      );

      // Recording must complete without throwing despite firestore exception
      await expectLater(sink.record(event), completes);
    },
  );
}
