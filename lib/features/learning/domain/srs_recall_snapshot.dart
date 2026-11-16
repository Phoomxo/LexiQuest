import 'dart:convert';

typedef SrsRecallSnapshot = ({
  String spelling,
  String meaning,
  String partOfSpeech,
});

String? encodeSrsRecallSnapshot(SrsRecallSnapshot? snapshot) {
  if (snapshot == null) return null;
  if (snapshot.spelling.trim().isEmpty || snapshot.meaning.trim().isEmpty) {
    throw ArgumentError('SRS recall requires a spelling and a meaning');
  }
  return jsonEncode({
    'v': 1,
    'kind': 'srsRecall',
    'spelling': snapshot.spelling,
    'meaning': snapshot.meaning,
    'partOfSpeech': snapshot.partOfSpeech,
  });
}

SrsRecallSnapshot decodeSrsRecallSnapshot(String source) {
  if (jsonDecode(source) case {
    'v': 1,
    'kind': 'srsRecall',
    'spelling': final String spelling,
    'meaning': final String meaning,
    'partOfSpeech': final String partOfSpeech,
  } when spelling.trim().isNotEmpty && meaning.trim().isNotEmpty) {
    return (spelling: spelling, meaning: meaning, partOfSpeech: partOfSpeech);
  }
  throw const FormatException('Invalid original SRS recall snapshot');
}
