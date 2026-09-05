import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_support_policy.dart';

void main() {
  test('PMT-022/023 support chronology is independent of repair role', () {
    expect(
      PairSupportPolicy.classify(
        supportRevision: 3,
        attemptRevision: 3,
      ).evidenceClass,
      EvidenceClass.recognition,
    );
    expect(
      PairSupportPolicy.classify(
        supportRevision: 3,
        attemptRevision: 4,
      ).evidenceClass,
      EvidenceClass.guidedPractice,
    );
    expect(
      PairSupportPolicy.classify(
        supportRevision: null,
        attemptRevision: 4,
      ).hintLevel,
      0,
    );
  });
  test('PMT-024 unavailable or private audio uses neutral local fallback', () {
    expect(
      PairSupportPolicy.audio(localAvailable: false),
      PairAudioDelivery.textAndIpa,
    );
    expect(
      PairSupportPolicy.audio(localAvailable: true),
      PairAudioDelivery.localPronunciation,
    );
  });
}
