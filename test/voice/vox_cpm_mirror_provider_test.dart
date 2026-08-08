import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_mirror_session_controller.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';
import 'package:vocab_learning_app/voice/vox_cpm_mirror_provider.dart';

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

VoiceRequest _mirrorRequest() => VoiceRequest.create(
  text: 'Cat',
  language: 'en',
  voiceId: 'mirror',
  speed: 1,
  contentId: 'word-cat',
  contentType: 'word',
  mode: VoiceMode.practice,
  capability: VoiceCapability.sessionVoiceMirror,
  privacyScope: VoicePrivacyScope.participantTransient,
);

VoiceRequest _standardRequest() => VoiceRequest.create(
  text: 'Cat',
  language: 'en',
  voiceId: 'teacher',
  speed: 1,
  contentId: 'word-cat',
  contentType: 'word',
  mode: VoiceMode.practice,
);

final class _RecordingController implements VoiceMirrorSessionControllerView {
  _RecordingController();

  final synthesizeCalls = <_SynthesizeArgs>[];
  VoiceFailure? synthesizeFailure;
  VoiceAudio? synthesizeResult;

  @override
  bool get hasConsent => true;

  @override
  bool get isActive => true;

  @override
  Future<VoiceAudio> synthesize({
    required String contentId,
    required String text,
    required String language,
  }) async {
    synthesizeCalls.add(
      _SynthesizeArgs(contentId: contentId, text: text, language: language),
    );
    final error = synthesizeFailure;
    if (error != null) throw error;
    return synthesizeResult ?? _defaultAudio();
  }
}

final class _SynthesizeArgs {
  const _SynthesizeArgs({
    required this.contentId,
    required this.text,
    required this.language,
  });

  final String contentId;
  final String text;
  final String language;
}

VoiceAudio _defaultAudio() => VoiceAudio(
  bytes: Uint8List.fromList([1, 2, 3]),
  requestId: 'req-mirror',
  engine: VoiceEngine.voxCpmMirror,
  modelVersion: '2.0.3',
  sampleRate: 48000,
);

void main() {
  group('descriptor', () {
    test('declares only participant-transient mirror capabilities', () {
      final provider = VoxCpmMirrorProvider(controller: _RecordingController());

      expect(provider.descriptor.engine, VoiceEngine.voxCpmMirror);
      expect(provider.descriptor.capabilities, {
        VoiceCapability.sessionVoiceMirror,
      });
      expect(
        provider.descriptor.privacyScope,
        VoicePrivacyScope.participantTransient,
      );
      expect(provider.descriptor.allowsStandardCache, isFalse);
    });
  });

  group('synthesize', () {
    test('forwards the learning target to the controller', () async {
      final controller = _RecordingController();
      final provider = VoxCpmMirrorProvider(controller: controller);

      final audio = await provider.synthesize(_mirrorRequest());

      expect(controller.synthesizeCalls.single, _matchesArgs());
      expect(audio.engine, VoiceEngine.voxCpmMirror);
      expect(audio.bytes, [1, 2, 3]);
    });

    test(
      'rejects standard-content requests before touching the controller',
      () async {
        final controller = _RecordingController();
        final provider = VoxCpmMirrorProvider(controller: controller);

        await expectLater(
          provider.synthesize(_standardRequest()),
          throwsA(_failure(VoiceFailureCategory.unsupportedCapability)),
        );
        expect(controller.synthesizeCalls, isEmpty);
      },
    );

    test(
      'propagates controller failures without rewriting the category',
      () async {
        final controller = _RecordingController()
          ..synthesizeFailure = const VoiceFailure(
            category: VoiceFailureCategory.sessionExpired,
            message: 'expired',
          );
        final provider = VoxCpmMirrorProvider(controller: controller);

        await expectLater(
          provider.synthesize(_mirrorRequest()),
          throwsA(_failure(VoiceFailureCategory.sessionExpired)),
        );
      },
    );
  });
}

Matcher _matchesArgs() {
  return isA<_SynthesizeArgs>()
      .having((args) => args.contentId, 'contentId', 'word-cat')
      .having((args) => args.text, 'text', 'Cat')
      .having((args) => args.language, 'language', 'en');
}
