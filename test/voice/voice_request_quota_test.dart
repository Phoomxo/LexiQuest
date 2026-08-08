import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_request_quota.dart';

VoiceRequest _request(String text) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1,
  contentId: 'dynamic',
  contentType: 'ai_tutor',
  mode: VoiceMode.practice,
  capability: VoiceCapability.dynamicTargetSpeech,
);

void main() {
  test('bounds request count and characters until reset', () async {
    final quota = VoiceRequestQuota(maxRequests: 2, maxCharacters: 6);

    expect(await quota.run(_request('Cat'), () async => 1), 1);
    expect(await quota.run(_request('Dog'), () async => 2), 2);
    await expectLater(
      quota.run(_request('Fox'), () async => 3),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.rateLimited,
        ),
      ),
    );

    quota.reset();
    expect(await quota.run(_request('Fox'), () async => 3), 3);
  });

  test('bounds concurrent work and releases the slot after failure', () async {
    final quota = VoiceRequestQuota(
      maxRequests: 3,
      maxCharacters: 30,
      maxConcurrent: 1,
    );
    final blocker = Completer<void>();
    final first = quota.run(_request('Cat'), () async {
      await blocker.future;
      return 1;
    });

    await expectLater(
      quota.run(_request('Dog'), () async => 2),
      throwsA(isA<VoiceFailure>()),
    );
    blocker.complete();
    expect(await first, 1);
    await expectLater(
      quota.run<int>(_request('Fox'), () async => throw StateError('failed')),
      throwsStateError,
    );
    quota.reset();
    expect(await quota.run(_request('Fox'), () async => 3), 3);
  });
}
