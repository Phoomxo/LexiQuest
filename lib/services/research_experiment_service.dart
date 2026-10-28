enum StudyArm { control, association, combined }

class ResearchParticipantConsent {
  final String participantId;
  final bool hasConsented;
  final StudyArm arm;
  final DateTime consentedAt;

  ResearchParticipantConsent({
    required this.participantId,
    required this.hasConsented,
    required this.arm,
    required this.consentedAt,
  });
}

class ResearchEvent {
  final String eventId;
  final String participantId;
  final StudyArm arm;
  final String eventType;
  final Map<String, dynamic> data;
  final DateTime occurredAt;

  ResearchEvent({
    required this.eventId,
    required this.participantId,
    required this.arm,
    required this.eventType,
    required this.data,
    required this.occurredAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'participantId': participantId,
      'arm': arm.name,
      'eventType': eventType,
      'data': data,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }
}

class ResearchExperimentService {
  final Map<String, ResearchParticipantConsent> _consents = {};
  final List<ResearchEvent> _eventLog = [];

  void recordConsent({
    required String participantId,
    required bool consent,
    required StudyArm arm,
  }) {
    _consents[participantId] = ResearchParticipantConsent(
      participantId: participantId,
      hasConsented: consent,
      arm: arm,
      consentedAt: DateTime.now().toUtc(),
    );
  }

  ResearchParticipantConsent? getConsent(String participantId) {
    return _consents[participantId];
  }

  bool logEvent({
    required String participantId,
    required String eventType,
    required Map<String, dynamic> data,
  }) {
    final consent = getConsent(participantId);
    if (consent == null || !consent.hasConsented) {
      return false; // Fail closed if not consented
    }

    // Sanitize: ensure no raw email/prompts/credentials
    final sanitizedData = Map<String, dynamic>.from(data)
      ..remove('email')
      ..remove('password')
      ..remove('token');

    final event = ResearchEvent(
      eventId: 'evt-${DateTime.now().millisecondsSinceEpoch}',
      participantId: participantId,
      arm: consent.arm,
      eventType: eventType,
      data: sanitizedData,
      occurredAt: DateTime.now().toUtc(),
    );

    _eventLog.add(event);
    return true;
  }

  List<ResearchEvent> getEventsForParticipant(String participantId) {
    return _eventLog.where((e) => e.participantId == participantId).toList();
  }
}
