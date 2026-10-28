import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/domain/speech_evidence_use_cases.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/voice/voice_mirror_recorder.dart';
import 'package:vocab_learning_app/voice/voice_mirror_session_controller.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';

void main() {
  testWidgets('uses real transcript provenance and never fabricates pitch', (
    tester,
  ) async {
    final voice = _FakeVoice();
    final speech = SpeechPracticeUseCases(_FakeSpeechGateway());
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Practice makes perfect',
          voiceProvider: voice,
          speechPractice: speech,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
    await tester.pumpAndSettle();
    expect(voice.requests.single.text, 'Practice makes perfect');

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
      findsOneWidget,
    );
    expect(find.textContaining('ความเหมือนของข้อความ: 100%'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้ส่งข้อมูล pitch หรือ phoneme'),
      findsOneWidget,
    );
    expect(find.textContaining('Pitch Contour'), findsNothing);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _FakeSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voiceProvider: _FakeVoice(),
          speechPractice: speech,
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(gateway.cancelCalls, 1);
  });

  group('voice mirror consent journey', () {
    testWidgets('defaults to no consent and shows the retention summary', (
      tester,
    ) async {
      final controller = _FakeMirrorController();
      final recorder = _FakeMirrorRecorder();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: controller,
            voiceMirrorRecorder: recorder,
          ),
        ),
      );

      final consent = find.byKey(const ValueKey('mirror-consent-switch'));
      final widget = tester.widget<SwitchListTile>(consent);
      expect(widget.value, isFalse);
      expect(find.textContaining('ลบเมื่อจบ'), findsOneWidget);
    });

    testWidgets('cannot enroll before granting consent', (tester) async {
      final controller = _FakeMirrorController();
      final recorder = _FakeMirrorRecorder();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: controller,
            voiceMirrorRecorder: recorder,
          ),
        ),
      );

      expect(find.byKey(const ValueKey('mirror-enroll-button')), findsNothing);
      expect(controller.startCalls, 0);
      expect(recorder.startCalls, 0);
    });

    testWidgets('grant consent then record and enroll reach ready', (
      tester,
    ) async {
      final controller = _FakeMirrorController();
      final recorder = _FakeMirrorRecorder();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: controller,
            voiceMirrorRecorder: recorder,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('mirror-consent-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mirror-enroll-button')));
      await tester.pumpAndSettle();

      expect(recorder.startCalls, 1);
      expect(recorder.stopCalls, 1);
      expect(controller.startCalls, 1);
      expect(find.byKey(const ValueKey('mirror-play-button')), findsOneWidget);
    });

    testWidgets('withdrawing consent ends the session', (tester) async {
      final controller = _FakeMirrorController();
      final recorder = _FakeMirrorRecorder();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: controller,
            voiceMirrorRecorder: recorder,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('mirror-consent-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mirror-enroll-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mirror-consent-switch')));
      await tester.pumpAndSettle();

      expect(controller.withdrawCalls, 1);
      expect(controller.endCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('leaving the screen ends the mirror session', (tester) async {
      final controller = _FakeMirrorController();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: controller,
            voiceMirrorRecorder: _FakeMirrorRecorder(),
          ),
        ),
      );

      // Removing the widget from the tree triggers dispose().
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(controller.onActivityLeaveCalls, 1);
    });

    testWidgets('shows no free-text field for mirror synthesis', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Hello',
            voiceProvider: _FakeVoice(),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
            voiceMirrorController: _FakeMirrorController(),
            voiceMirrorRecorder: _FakeMirrorRecorder(),
          ),
        ),
      );

      expect(find.byType(TextField), findsNothing);
    });
  });

  group('speech evidence persistence', () {
    testWidgets('persists the real transcript, score, and provenance', (
      tester,
    ) async {
      final gateway = _FakeSpeechGateway();
      final speech = SpeechPracticeUseCases(gateway);
      final evidence = _RecordingSpeechEvidence();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Practice makes perfect',
            voiceProvider: _FakeVoice(),
            speechPractice: speech,
            speechEvidence: evidence.useCases,
            sessionId: 'session:test',
            wordId: 'word:test',
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
      await tester.pumpAndSettle();

      expect(evidence.records, hasLength(1));
      final record = evidence.records.single;
      expect(record.promptMode, 'shadowing');
      expect(record.recognizedTranscript, 'Practice makes perfect');
      expect(record.similarityScore, 100);
      expect(record.isExactMatch, isTrue);
      expect(record.sttEngine, 'platform-speech-recognizer');
      expect(record.similarityAlgorithm, 'transcript-edit-distance-v1');
      expect(record.locale, 'en-US');
      expect(record.unavailableReason, isNull);
    });

    testWidgets('silence persists an unavailable reason without a score', (
      tester,
    ) async {
      final gateway = _FakeSpeechGateway()
        ..finalTranscript = ''
        ..emitFinal = true;
      final speech = SpeechPracticeUseCases(gateway);
      final evidence = _RecordingSpeechEvidence();
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Practice makes perfect',
            voiceProvider: _FakeVoice(),
            speechPractice: speech,
            speechEvidence: evidence.useCases,
            sessionId: 'session:silence',
            wordId: 'word:silence',
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
      await tester.pumpAndSettle();

      expect(evidence.records, hasLength(1));
      final record = evidence.records.single;
      expect(record.similarityScore, isNull);
      expect(record.unavailableReason, 'silence');
    });
  });
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  _FakeSpeechGateway({String? finalTranscript})
    : finalTranscript = finalTranscript ?? 'Practice makes perfect';

  int cancelCalls = 0;
  String finalTranscript;
  bool emitFinal = true;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: finalTranscript,
        isFinal: emitFinal,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'platform-speech-recognizer',
        locale: locale,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FakeVoice implements VoiceProvider {
  final List<VoiceRequest> requests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

final class _FakeMirrorController implements VoiceMirrorSessionController {
  int startCalls = 0;
  int endCalls = 0;
  int withdrawCalls = 0;
  int onActivityLeaveCalls = 0;
  bool _hasConsent = false;
  bool _active = false;

  @override
  bool get hasConsent => _hasConsent;

  @override
  bool get isActive => _active;

  @override
  Future<void> grantConsent() async {
    _hasConsent = true;
  }

  @override
  Future<void> withdrawConsent() async {
    _hasConsent = false;
    withdrawCalls += 1;
    await end();
  }

  @override
  Future<void> start({required Uint8List enrollmentWav}) async {
    startCalls += 1;
    _active = true;
  }

  @override
  Future<VoiceAudio> synthesize({
    required String contentId,
    required String text,
    required String language,
  }) async {
    return VoiceAudio(
      bytes: Uint8List.fromList([1]),
      requestId: 'req',
      engine: VoiceEngine.voxCpmMirror,
      modelVersion: '2.0.3',
      sampleRate: 48000,
    );
  }

  @override
  Future<void> end() async {
    endCalls += 1;
    _active = false;
  }

  @override
  Future<void> onAccountChanged() async => end();

  @override
  Future<void> onActivityLeave() async {
    onActivityLeaveCalls += 1;
    await end();
  }

  @override
  Future<void> renewLease() async {}

  @override
  Future<void> dispose() async => end();

  @override
  void onAppLifecycleStateChanged(AppLifecycleState state) {}
}

final class _FakeMirrorRecorder implements VoiceMirrorRecorder {
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  String? get currentFilePath => null;

  @override
  bool get isRecording => false;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<Uint8List> stop() async {
    stopCalls += 1;
    return Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x57, 0x41, 0x56, 0x45]);
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> purgeStaleFiles() async {}
}

final class _RecordingSpeechEvidence implements SpeechEvidenceRepository {
  final records = <RecordSpeechEvidenceCommand>[];

  late final SpeechEvidenceUseCases useCases = SpeechEvidenceUseCases(
    owners: _FakeLocalOwnerRepository(),
    repository: this,
    nowUtc: () => DateTime.utc(2026, 7, 31),
    generateId: _idCounter,
  );

  int _counter = 0;
  String _idCounter() => 'test-${_counter++}';

  @override
  Future<String> recordSpeechEvidence(
    RecordSpeechEvidenceCommand command,
  ) async {
    records.add(command);
    return command.id;
  }
}

final class _FakeLocalOwnerRepository implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'local:test', createdAtUtc: DateTime.utc(2026, 7, 31));

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async =>
      LocalOwner(id: 'local:test', createdAtUtc: DateTime.utc(2026, 7, 31));
}
