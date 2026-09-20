import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../learning/domain/context_practice.dart';

enum ProbeTiming { tooEarly, noDistinctContext, clockUncertain, unverified }

abstract final class TransferProbePolicy {
  static const revision = 'personal-transfer-1';
  static const minimumDelay = Duration(hours: 24);
  static ProbeTiming evaluate({
    required DateTime origin,
    required DateTime now,
    required bool distinct,
    Duration? observedElapsed,
  }) {
    if (!origin.isUtc ||
        !now.isUtc ||
        origin.millisecondsSinceEpoch < 0 ||
        now.isBefore(origin) ||
        observedElapsed != null &&
            (observedElapsed.isNegative ||
                (now.difference(origin) - observedElapsed).abs() >
                    const Duration(seconds: 5))) {
      return ProbeTiming.clockUncertain;
    }
    if (!distinct) return ProbeTiming.noDistinctContext;
    if (now.difference(origin) < minimumDelay) return ProbeTiming.tooEarly;
    // A local clock (including monotonic duration) is not trusted UTC.
    return ProbeTiming.unverified;
  }
}

final class TransferProbeItem {
  const TransferProbeItem(this.answer, this.variant, this.sentence);
  final String answer, variant, sentence;
  int get revision => 1;
  String get wordId => 'word:starter-$answer';
  String get id => 'transfer:$answer:$variant';
  String get contextHash => sha256.convert(utf8.encode(sentence)).toString();
  String get originContextHash => sha256
      .convert(
        utf8.encode(const ContextPracticeInventory().find(wordId)!.sentence),
      )
      .toString();
  String get prompt => sentence.replaceFirst(answer, '_____');
  String evidenceHash({
    required String coreHash,
    required String lexicalHash,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'policy': TransferProbePolicy.revision,
            'item': toJson(),
            'coreHash': coreHash,
            'lexicalHash': lexicalHash,
          }),
        ),
      )
      .toString();
  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'wordId': wordId,
    'contextHash': contextHash,
    'sentence': sentence,
  };
}

abstract final class TransferProbeInventory {
  static const items = <TransferProbeItem>[
    TransferProbeItem(
      'book',
      'a',
      'At the library, she borrowed a book with a hundred pages.',
    ),
    TransferProbeItem(
      'book',
      'b',
      'He opened a book and turned to page ten to read the story.',
    ),
    TransferProbeItem(
      'pencil',
      'a',
      'The artist sharpened a pencil before drawing the tree.',
    ),
    TransferProbeItem(
      'pencil',
      'b',
      'Use a pencil for this sketch so you can erase the lines.',
    ),
    TransferProbeItem(
      'bottle',
      'a',
      'She unscrewed the cap of the bottle and drank the water.',
    ),
    TransferProbeItem(
      'bottle',
      'b',
      'The glass bottle has a narrow neck and holds olive oil.',
    ),
  ];
  static String get fingerprint => sha256
      .convert(
        utf8.encode(jsonEncode([for (final item in items) item.toJson()])),
      )
      .toString();
}
