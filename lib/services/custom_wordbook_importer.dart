import 'dart:convert';

class CustomWordbookImporter {
  const CustomWordbookImporter();

  /// Parses JSON string format: [{"word": "apple", "translation": "แอปเปิ้ล", "example": "An apple"}]
  List<Map<String, String>> parseJson(String jsonRaw) {
    if (jsonRaw.trim().isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonRaw);
      return decoded
          .map((item) {
            if (item is Map<String, dynamic>) {
              return {
                'word': item['word']?.toString() ?? '',
                'translation': item['translation']?.toString() ?? '',
                'example': item['example']?.toString() ?? '',
              };
            }
            return <String, String>{};
          })
          .where((element) => element['word']?.isNotEmpty ?? false)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Parses CSV format: word,translation,example
  List<Map<String, String>> parseCsv(String csvRaw) {
    if (csvRaw.trim().isEmpty) return [];
    final lines = LineSplitter.split(csvRaw).toList();
    final result = <Map<String, String>>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
        final word = parts[0].trim();
        final translation = parts.length > 1 ? parts[1].trim() : '';
        final example = parts.length > 2
            ? parts.sublist(2).join(',').trim()
            : '';
        result.add({
          'word': word,
          'translation': translation,
          'example': example,
        });
      }
    }
    return result;
  }
}
