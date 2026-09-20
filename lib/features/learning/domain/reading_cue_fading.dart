/// Removes inline meaning cues only from the app's generated glossary format.
/// Ordinary passages remain byte-for-byte unchanged. This is a view transform:
/// the persisted document and its checksum remain the recovery authority.
String cueFadedReadingPassage({
  required String passage,
  required String? documentId,
  required List<String> targetWords,
}) {
  if (documentId == null ||
      !RegExp(r'^associative-reading:[0-9a-f]{64}$').hasMatch(documentId) ||
      targetWords.isEmpty ||
      targetWords.any((word) => word.trim().isEmpty)) {
    return passage;
  }
  var cursor = 0;
  for (var index = 0; index < targetWords.length; index++) {
    final prefix = '${targetWords[index]} means ';
    if (!passage.startsWith(prefix, cursor)) return passage;
    final meaningStart = cursor + prefix.length;
    final last = index == targetWords.length - 1;
    final meaningEnd = last
        ? passage.length - 1
        : passage.indexOf('. ${targetWords[index + 1]} means ', meaningStart);
    if (meaningEnd <= meaningStart ||
        (last && !passage.endsWith('.')) ||
        passage.substring(meaningStart, meaningEnd).trim().isEmpty) {
      return passage;
    }
    cursor = meaningEnd + 2;
  }
  return '${targetWords.join('. ')}.';
}
