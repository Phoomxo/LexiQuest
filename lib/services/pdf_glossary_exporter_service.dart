class PdfGlossaryExporterService {
  const PdfGlossaryExporterService();

  /// Formats personal vocabulary lists into a printable study book layout text.
  String generateGlossaryDocument(List<Map<String, String>> wordList) {
    final buffer = StringBuffer();
    buffer.writeln('==========================================');
    buffer.writeln('  LEXIQUEST PERSONAL VOCABULARY GLOSSARY');
    buffer.writeln('==========================================\n');

    for (var i = 0; i < wordList.length; i++) {
      final item = wordList[i];
      final word = item['word'] ?? '';
      final translation = item['translation'] ?? '';
      final example = item['example'] ?? '';

      buffer.writeln('${i + 1}. $word');
      buffer.writeln('   คำแปล: $translation');
      if (example.isNotEmpty) {
        buffer.writeln('   ประโยคตัวอย่าง: "$example"');
      }
      buffer.writeln('------------------------------------------');
    }

    return buffer.toString();
  }
}
