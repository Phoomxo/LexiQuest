import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../learning/domain/context_practice.dart';
import '../../learning_packs/domain/sense_crosswalk.dart';

enum AudioLessonFormat { wordAndExample, shortScenario }

/// Original bounded scripts, source/AI-assisted engineering review 2026-09-20.
/// No independent human, CEFR, alignment or acoustic validation is claimed.
final class AudioLessonScript {
  AudioLessonScript._(this.sense, this.format, List<String> segments)
    : segments = List.unmodifiable(segments);
  final SenseRef sense;
  final AudioLessonFormat format;
  final List<String> segments;
  static const revision = 1;
  static const _scripts = {
    'book': [
      'A book has pages that you can read. Listen to the word: book.',
      'I read a book at home. In this sentence, book names the thing I read.',
      'You are choosing something to read at home. You pick up a book and open its pages.',
      'You say, I want to read this book. Here, book means the object with pages, not the action of making a reservation.',
    ],
    'pencil': [
      'A pencil is a tool for writing or drawing. Listen to the word: pencil.',
      'I write with a pencil. In this sentence, pencil names the tool I use.',
      'You are drawing a small house. You use a pencil, then erase a line you want to change.',
      'You say, I draw with a pencil. Here, pencil means a writing or drawing tool, not a book you read.',
    ],
    'bottle': [
      'A bottle is a container with a narrow neck. Listen to the word: bottle.',
      'I pour water from a bottle. In this sentence, bottle names the container.',
      'You want some water. You open a bottle and pour water from its narrow neck into a cup.',
      'You say, The water is in the bottle. Here, bottle names the container holding the water, not the water itself.',
    ],
  };
  factory AudioLessonScript.forSense(SenseRef sense, AudioLessonFormat format) {
    final entry = const ContextPracticeInventory().find(sense.wordId);
    if (entry == null ||
        sense.senseKey != 'starter-object-v1' ||
        sense.senseRevision != 1 ||
        sense.lexicalArtifactHash != entry.artifactHash) {
      throw StateError('Reviewed audio script unavailable for this sense');
    }
    final offset = format == AudioLessonFormat.wordAndExample ? 0 : 2;
    return AudioLessonScript._(
      sense,
      format,
      _scripts[entry.answer]!.sublist(offset, offset + 2),
    );
  }
  String get transcript => segments.join('\n\n');
  Map<String, Object?> toJson() => {
    'scriptRevision': revision,
    'sense': sense.toJson(),
    'format': format.name,
    'segments': segments,
    'alignment': 'none',
    'reviewProvenance': 'original-source-ai-engineering-review-2026-09-20',
  };
  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}
