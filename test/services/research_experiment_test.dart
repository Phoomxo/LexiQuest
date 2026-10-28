import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/research_experiment_service.dart';

void main() {
  group('B6 Research Experiment & Analytics Tests', () {
    late ResearchExperimentService service;

    setUp(() {
      service = ResearchExperimentService();
    });

    test('Requires consent before logging research events', () {
      final successUnconsented = service.logEvent(
        participantId: 'p123',
        eventType: 'recall_test',
        data: {'wordKey': 'ephemeral', 'correct': true},
      );
      expect(successUnconsented, isFalse);

      service.recordConsent(
        participantId: 'p123',
        consent: true,
        arm: StudyArm.combined,
      );

      final successConsented = service.logEvent(
        participantId: 'p123',
        eventType: 'recall_test',
        data: {
          'wordKey': 'ephemeral',
          'correct': true,
          'email': 'private@test.com',
        },
      );
      expect(successConsented, isTrue);

      final events = service.getEventsForParticipant('p123');
      expect(events.length, 1);
      expect(events.first.arm, StudyArm.combined);
      expect(events.first.data.containsKey('email'), isFalse); // Sanitized
    });
  });
}
