import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cefr_word.dart';

class CefrService {
  final http.Client _client;

  CefrService({http.Client? client}) : _client = client ?? http.Client();

  static const List<CefrWord> defaultCefrDatabase = [
    // A1 Beginner
    CefrWord(
      word: 'hello',
      cefrLevel: 'A1',
      category: 'Daily Life',
      meaning: 'สวัสดี',
      partOfSpeech: 'Interjection',
      exampleSentence: 'Hello, how are you?',
      tags: ['daily'],
    ),
    CefrWord(
      word: 'dog',
      cefrLevel: 'A1',
      category: 'Animals',
      meaning: 'หมา / สุนัข',
      partOfSpeech: 'Noun',
      exampleSentence: 'The dog is barking.',
      tags: ['daily'],
    ),
    CefrWord(
      word: 'apple',
      cefrLevel: 'A1',
      category: 'Food',
      meaning: 'แอปเปิ้ล',
      partOfSpeech: 'Noun',
      exampleSentence: 'She eats a red apple.',
      tags: ['daily'],
    ),
    CefrWord(
      word: 'book',
      cefrLevel: 'A1',
      category: 'Academic',
      meaning: 'หนังสือ',
      partOfSpeech: 'Noun',
      exampleSentence: 'I read an interesting book.',
      tags: ['daily'],
    ),

    // A2 Elementary
    CefrWord(
      word: 'journey',
      cefrLevel: 'A2',
      category: 'Travel',
      meaning: 'การเดินทาง',
      partOfSpeech: 'Noun',
      exampleSentence: 'Have a safe journey.',
      tags: ['daily', 'toeic'],
    ),
    CefrWord(
      word: 'weather',
      cefrLevel: 'A2',
      category: 'Daily Life',
      meaning: 'สภาพอากาศ',
      partOfSpeech: 'Noun',
      exampleSentence: 'The weather is nice today.',
      tags: ['daily'],
    ),
    CefrWord(
      word: 'borrow',
      cefrLevel: 'A2',
      category: 'Academic',
      meaning: 'ยืม',
      partOfSpeech: 'Verb',
      exampleSentence: 'Can I borrow your pen?',
      tags: ['daily'],
    ),

    // B1 Intermediate
    CefrWord(
      word: 'achieve',
      cefrLevel: 'B1',
      category: 'Work/Business',
      meaning: 'บรรลุเป้าหมาย',
      partOfSpeech: 'Verb',
      exampleSentence: 'He achieved his dream.',
      tags: ['toeic', 'ielts'],
    ),
    CefrWord(
      word: 'opportunity',
      cefrLevel: 'B1',
      category: 'Work/Business',
      meaning: 'โอกาส',
      partOfSpeech: 'Noun',
      exampleSentence: 'This is a great opportunity.',
      tags: ['toeic', 'ielts'],
    ),
    CefrWord(
      word: 'challenge',
      cefrLevel: 'B1',
      category: 'Academic',
      meaning: 'ความท้าทาย',
      partOfSpeech: 'Noun',
      exampleSentence: 'I accept this learning challenge.',
      tags: ['ielts'],
    ),

    // B2 Upper-Intermediate
    CefrWord(
      word: 'innovative',
      cefrLevel: 'B2',
      category: 'Technology',
      meaning: 'ที่เป็นนวัตกรรมใหม่',
      partOfSpeech: 'Adjective',
      exampleSentence: 'They launched an innovative product.',
      tags: ['toeic', 'ielts'],
    ),
    CefrWord(
      word: 'perspective',
      cefrLevel: 'B2',
      category: 'Academic',
      meaning: 'มุมมอง / ทัศนคติ',
      partOfSpeech: 'Noun',
      exampleSentence: 'Consider things from a different perspective.',
      tags: ['ielts', 'toefl'],
    ),
    CefrWord(
      word: 'sustainable',
      cefrLevel: 'B2',
      category: 'Science',
      meaning: 'ยั่งยืน',
      partOfSpeech: 'Adjective',
      exampleSentence: 'We need sustainable energy sources.',
      tags: ['ielts', 'toefl'],
    ),

    // C1 Advanced
    CefrWord(
      word: 'meticulous',
      cefrLevel: 'C1',
      category: 'Work/Business',
      meaning: 'พิถีพิถัน / ละเอียดถี่ถ้วน',
      partOfSpeech: 'Adjective',
      exampleSentence: 'She is meticulous about her work.',
      tags: ['ielts', 'toefl'],
    ),
    CefrWord(
      word: 'ubiquitous',
      cefrLevel: 'C1',
      category: 'Technology',
      meaning: 'แพร่หลาย / มีอยู่ทุกหนแห่ง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Smartphones are ubiquitous nowadays.',
      tags: ['ielts', 'toefl'],
    ),
    CefrWord(
      word: 'pragmatic',
      cefrLevel: 'C1',
      category: 'Academic',
      meaning: 'เน้นการปฏิบัติจริง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'We must take a pragmatic approach.',
      tags: ['ielts', 'toefl'],
    ),

    // C2 Proficiency
    CefrWord(
      word: 'ephemeral',
      cefrLevel: 'C2',
      category: 'Philosophy',
      meaning: 'ชั่วคราว / ดำรงอยู่เพียงประเดี๋ยวเดียว',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Fame is often ephemeral.',
      tags: ['toefl'],
    ),
    CefrWord(
      word: 'quintessential',
      cefrLevel: 'C2',
      category: 'Philosophy',
      meaning: 'เป็นแบบอย่างอันแท้จริง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'This is the quintessential English village.',
      tags: ['toefl'],
    ),
    CefrWord(
      word: 'perspicacious',
      cefrLevel: 'C2',
      category: 'Philosophy',
      meaning: 'ที่มีสายตายาวไกล / เฉียบแหลม',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Her perspicacious insight solved the problem.',
      tags: ['toefl'],
    ),
  ];

  List<String> getAvailableCategories({String? level}) {
    final list = filter(level: level);
    return list.map((w) => w.category).toSet().toList()..sort();
  }

  /// Multi-dimensional filter by level, category, tag, and search query
  List<CefrWord> filter({
    String? level,
    String? category,
    String? tag,
    String? searchQuery,
  }) {
    return defaultCefrDatabase.where((word) {
      if (level != null && level.isNotEmpty && level.toUpperCase() != 'ALL') {
        if (word.cefrLevel.toUpperCase() != level.toUpperCase()) return false;
      }
      if (category != null &&
          category.isNotEmpty &&
          category.toUpperCase() != 'ALL') {
        if (word.category.toLowerCase() != category.toLowerCase()) return false;
      }
      if (tag != null && tag.isNotEmpty && tag.toUpperCase() != 'ALL') {
        if (!word.tags.contains(tag.toLowerCase())) return false;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final query = searchQuery.trim().toLowerCase();
        final matchWord = word.word.toLowerCase().contains(query);
        final matchMeaning = word.meaning.toLowerCase().contains(query);
        if (!matchWord && !matchMeaning) return false;
      }
      return true;
    }).toList();
  }

  List<CefrWord> getWordsByLevel(String level) => filter(level: level);

  /// Queries Free Dictionary API and Google Translate API to enrich CEFR words
  Future<CefrWord> fetchAndEnrichCefrWord(
    String word,
    String level, {
    String category = 'General',
  }) async {
    String partOfSpeech = 'Noun';
    String meaning = '';
    String example = '';

    try {
      final dictUri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/$word',
      );
      final dictRes = await _client.get(dictUri);
      if (dictRes.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(dictRes.body);
        if (jsonList.isNotEmpty && jsonList.first['meanings'] != null) {
          final meaningsList = jsonList.first['meanings'] as List;
          if (meaningsList.isNotEmpty) {
            partOfSpeech = meaningsList.first['partOfSpeech'] ?? 'Noun';
            final defs = meaningsList.first['definitions'] as List?;
            if (defs != null && defs.isNotEmpty) {
              example = defs.first['example'] ?? '';
            }
          }
        }
      }

      final transUri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=th&dt=t&q=$word',
      );
      final transRes = await _client.get(transUri);
      if (transRes.statusCode == 200) {
        final List<dynamic> transJson = jsonDecode(transRes.body);
        if (transJson.isNotEmpty && transJson.first is List) {
          final List firstPart = transJson.first as List;
          if (firstPart.isNotEmpty && firstPart.first is List) {
            meaning = (firstPart.first as List).first?.toString() ?? '';
          }
        }
      }
    } catch (_) {}

    return CefrWord(
      word: word,
      cefrLevel: level.toUpperCase(),
      category: category,
      meaning: meaning.isNotEmpty ? meaning : 'คำแปล $word',
      partOfSpeech: partOfSpeech,
      exampleSentence: example.isNotEmpty
          ? example
          : 'Example sentence for $word.',
    );
  }
}
