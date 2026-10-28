import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/suggestion_model.dart';
import 'dart:math';

class SuggestionService {
  /// 🔥 ดึงคำศัพท์จาก Datamuse API หรือสุ่มคำ ถ้าหมวดหมู่ไม่มีความหมาย
  Future<List<SuggestedWord>> fetchWords(String category, int limit) async {
    if (_isThai(category)) {
      category = await _translateToEnglish(category);
    }

    // ✅ เพิ่มค่า Noise เพื่อเปลี่ยนผลลัพธ์
    final noiseWords = ["random", "unique", "different", "variety", "shuffle"];
    final randomNoise = noiseWords[Random().nextInt(noiseWords.length)];
    final cacheBuster = Random().nextInt(10000); // ✅ ป้องกัน API แคชผลลัพธ์

    final url = Uri.parse(
        'https://api.datamuse.com/words?ml=${_sanitizeQuery(category)}+$randomNoise&max=$limit&md=p&nocache=$cacheBuster');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      if (data.isEmpty) {
        return getRandomWords(limit);
      }

      // ✅ ใช้ Set เพื่อป้องกันคำซ้ำ
      Set<String> seenWords = {};
      List<SuggestedWord> words = [];

      for (var wordData in data) {
        String word = wordData['word'];
        if (seenWords.contains(word)) continue; // ✅ กรองคำที่ซ้ำออก

        String pos = "unknown";
        if (wordData.containsKey('tags')) {
          List<String> tags = List<String>.from(wordData['tags']);
          pos = _extractPartOfSpeech(tags);
        }

        words.add(SuggestedWord(
          word: word,
          meaning: "กำลังแปล...",
          partOfSpeech: pos,
        ));
        seenWords.add(word);
      }

      // ✅ สุ่มตำแหน่งของคำให้แตกต่างกัน
      words.shuffle();

      return await _translateWords(words);
    } else {
      throw Exception("Error fetching words");
    }
  }

  /// 🔥 แปลคำศัพท์จากอังกฤษ → ไทย (Batch Translation)
  Future<List<SuggestedWord>> _translateWords(List<SuggestedWord> words) async {
    List<String> wordsToTranslate = words.map((w) => w.word).toList();
    List<String> translatedTexts = await _batchTranslateToThai(wordsToTranslate);

    for (var i = 0; i < words.length; i++) {
      words[i] = SuggestedWord(
        word: words[i].word,
        meaning: (i < translatedTexts.length && translatedTexts[i].isNotEmpty)
            ? translatedTexts[i]
            : "ไม่มีคำแปล",
        partOfSpeech: words[i].partOfSpeech,
      );
    }
    return words;
  }

  /// 🔥 Batch Translate หลายคำพร้อมกัน
  Future<List<String>> _batchTranslateToThai(List<String> words) async {
    List<String> translations = [];

    try {
      for (int i = 0; i < words.length; i += 5) {
        List<String> batch = words.sublist(i, (i + 5 > words.length) ? words.length : i + 5);
        String query = batch.join("%0A"); // ✅ ใช้ newline เพื่อให้ API แยกแต่ละคำ
        final url = Uri.parse(
            'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=th&dt=t&dt=at&q=$query');

        final response = await http.get(url);
        print("📌 Google Translate API Response: ${response.body}");

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);

          if (data.isNotEmpty && data[0] is List) {
            List<String> batchTranslations = [];

            for (var item in data[0]) {
              if (item is List && item.isNotEmpty) {
                batchTranslations.add(item[0].toString());
              }
            }

            while (batchTranslations.length < batch.length) {
              batchTranslations.add("ไม่มีคำแปล");
            }

            translations.addAll(batchTranslations);
          }
        }
      }
    } catch (e) {
      print("❌ Error translating words: $e");
      translations = List.filled(words.length, "ไม่มีคำแปล");
    }

    return translations.length >= words.length ? translations.sublist(0, words.length) : translations;
  }

  /// 🔥 ตรวจสอบว่าหมวดหมู่เป็นภาษาไทยหรือไม่
  bool _isThai(String text) {
    return RegExp(r'[\u0E00-\u0E7F]').hasMatch(text);
  }

  /// 🔥 แปลชื่อหมวดหมู่จากไทย → อังกฤษ ก่อนใช้ Datamuse
  Future<String> _translateToEnglish(String text) async {
    try {
      final url = Uri.parse(
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=th&tl=en&dt=t&q=$text');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty && data[0] is List && data[0][0] is List) {
          return data[0][0][0].toString();
        }
      }
    } catch (e) {
      print("❌ Error translating category: $e");
    }
    return text;
  }

  /// 🔥 ฟังก์ชันแยกประเภทของคำ (POS)
  String _extractPartOfSpeech(List<String> tags) {
    if (tags.contains("n")) return "noun";
    if (tags.contains("v")) return "verb";
    if (tags.contains("adj")) return "adjective";
    if (tags.contains("adv")) return "adverb";
    if (tags.contains("prep")) return "preposition";
    return "unknown";
  }

  /// 🔥 ฟังก์ชันสุ่มคำศัพท์ (ใช้แทนเมื่อไม่มีคำที่เกี่ยวข้อง)
  List<SuggestedWord> getRandomWords(int limit) {
    List<String> randomWords = [
      "Sunshine", "Ocean", "Harmony", "Discovery", "Innovation", "Momentum",
      "Adventure", "Galaxy", "Breeze", "Thunder", "Echo", "Serenity",
      "Storm", "Cloud", "Rain", "Tornado", "Mist", "Horizon", "Frost", "Glacier"
    ];

    List<String> partOfSpeechList = ["noun", "verb", "adjective", "adverb"];

    return List.generate(limit, (index) {
      return SuggestedWord(
        word: randomWords[Random().nextInt(randomWords.length)], // ✅ สุ่มจริงๆ
        meaning: "คำที่ถูกสุ่ม",
        partOfSpeech: partOfSpeechList[index % partOfSpeechList.length],
      );
    });
  }

  /// 🔥 ฟังก์ชันจัดการ Query String เพื่อลดข้อผิดพลาดของ API
  String _sanitizeQuery(String query) {
    return query.replaceAll(" ", "+").toLowerCase();
  }
}
