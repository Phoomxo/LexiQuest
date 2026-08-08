enum VoiceCapability {
  standardTargetSpeech,
  dynamicTargetSpeech,
  sessionVoiceMirror,
  speechToText,
  pronunciationEvidence,
}

extension VoiceCapabilityKind on VoiceCapability {
  bool get isSpeechSynthesis =>
      this != VoiceCapability.speechToText &&
      this != VoiceCapability.pronunciationEvidence;
}

enum VoicePrivacyScope { standardContent, participantTransient }
