import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/domain/audio_lesson.dart';
import 'package:vocab_learning_app/features/learning/domain/context_practice.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';

void main() {
  for (final e in ContextPracticeInventory.entries) {
    for (final format in AudioLessonFormat.values) {
      test('${e.answer} ${format.name} pins bounded transcript and sense', () {
        final sense = SenseRef.fromJson({
          'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
          'wordId': e.wordId,
          'senseKey': 'starter-object-v1',
          'senseRevision': 1,
          'lexicalArtifactHash': e.artifactHash,
        });
        final script = AudioLessonScript.forSense(sense, format);
        expect(script.segments, hasLength(2));
        expect(script.transcript, script.segments.join('\n\n'));
        expect(
          script.segments.every((s) => s.length <= 500 && s.contains(e.answer)),
          isTrue,
        );
        expect(script.fingerprint, hasLength(64));
        expect(script.toJson()['alignment'], 'none');
        expect(() => script.segments.add('mutable'), throwsUnsupportedError);
        expect(
          () => AudioLessonScript.forSense(
            SenseRef.fromJson({...sense.toJson(), 'senseRevision': 2}),
            format,
          ),
          throwsStateError,
        );
        expect(
          () => AudioLessonScript.forSense(
            SenseRef.fromJson({
              ...sense.toJson(),
              'lexicalArtifactHash': '0' * 64,
            }),
            format,
          ),
          throwsStateError,
        );
      });
    }
  }
}
