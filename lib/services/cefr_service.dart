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
      meaning: 'สวัสดี',
      partOfSpeech: 'Interjection',
      exampleSentence: 'Hello, how are you?',
    ),
    CefrWord(
      word: 'apple',
      cefrLevel: 'A1',
      meaning: 'แอปเปิ้ล',
      partOfSpeech: 'Noun',
      exampleSentence: 'She eats a red apple.',
    ),
    CefrWord(
      word: 'book',
      cefrLevel: 'A1',
      meaning: 'หนังสือ',
      partOfSpeech: 'Noun',
      exampleSentence: 'I read an interesting book.',
    ),

    // A2 Elementary
    CefrWord(
      word: 'journey',
      cefrLevel: 'A2',
      meaning: 'การเดินทาง',
      partOfSpeech: 'Noun',
      exampleSentence: 'Have a safe journey.',
    ),
    CefrWord(
      word: 'weather',
      cefrLevel: 'A2',
      meaning: 'สภาพอากาศ',
      partOfSpeech: 'Noun',
      exampleSentence: 'The weather is nice today.',
    ),
    CefrWord(
      word: 'borrow',
      cefrLevel: 'A2',
      meaning: 'ยืม',
      partOfSpeech: 'Verb',
      exampleSentence: 'Can I borrow your pen?',
    ),

    // B1 Intermediate
    CefrWord(
      word: 'achieve',
      cefrLevel: 'B1',
      meaning: 'บรรลุเป้าหมาย',
      partOfSpeech: 'Verb',
      exampleSentence: 'He achieved his dream.',
    ),
    CefrWord(
      word: 'opportunity',
      cefrLevel: 'B1',
      meaning: 'โอกาส',
      partOfSpeech: 'Noun',
      exampleSentence: 'This is a great opportunity.',
    ),
    CefrWord(
      word: 'challenge',
      cefrLevel: 'B1',
      meaning: 'ความท้าทาย',
      partOfSpeech: 'Noun',
      exampleSentence: 'I accept this learning challenge.',
    ),

    // B2 Upper-Intermediate
    CefrWord(
      word: 'innovative',
      cefrLevel: 'B2',
      meaning: 'ที่เป็นนวัตกรรมใหม่',
      partOfSpeech: 'Adjective',
      exampleSentence: 'They launched an innovative product.',
    ),
    CefrWord(
      word: 'perspective',
      cefrLevel: 'B2',
      meaning: 'มุมมอง / ทัศนคติ',
      partOfSpeech: 'Noun',
      exampleSentence: 'Consider things from a different perspective.',
    ),
    CefrWord(
      word: 'sustainable',
      cefrLevel: 'B2',
      meaning: 'ยั่งยืน',
      partOfSpeech: 'Adjective',
      exampleSentence: 'We need sustainable energy sources.',
    ),

    // C1 Advanced
    CefrWord(
      word: 'meticulous',
      cefrLevel: 'C1',
      meaning: 'พิถีพิถัน / ละเอียดถี่ถ้วน',
      partOfSpeech: 'Adjective',
      exampleSentence: 'She is meticulous about her work.',
    ),
    CefrWord(
      word: 'ubiquitous',
      cefrLevel: 'C1',
      meaning: 'แพร่หลาย / มีอยู่ทุกหนแห่ง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Smartphones are ubiquitous nowadays.',
    ),
    CefrWord(
      word: 'pragmatic',
      cefrLevel: 'C1',
      meaning: 'เน้นการปฏิบัติจริง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'We must take a pragmatic approach.',
    ),

    // C2 Proficiency
    CefrWord(
      word: 'ephemeral',
      cefrLevel: 'C2',
      meaning: 'ชั่วคราว / ดำรงอยู่เพียงประเดี๋ยวเดียว',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Fame is often ephemeral.',
    ),
    CefrWord(
      word: 'quintessential',
      cefrLevel: 'C2',
      meaning: 'เป็นแบบอย่างอันแท้จริง',
      partOfSpeech: 'Adjective',
      exampleSentence: 'This is the quintessential English village.',
    ),
    CefrWord(
      word: 'perspicacious',
      cefrLevel: 'C2',
      meaning: 'ที่มีสายตายาวไกล / เฉียบแหลม',
      partOfSpeech: 'Adjective',
      exampleSentence: 'Her perspicacious insight solved the problem.',
    ),
  ];

  List<CefrWord> getWordsByLevel(String level) {
    final normalized = level.trim().toUpperCase();
    return defaultCefrDatabase.where((w) => w.cefrLevel == normalized).toList();
  }

  /// Queries Free Dictionary API and Google Translate API to enrich CEFR words
  Future<CefrWord> fetchAndEnrichCefrWord(String word, String level) async {
    String partOfSpeech = 'Noun';
    String meaning = '';
    String example = '';

    try {
      // 1. Dictionary API
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

      // 2. Google Translate API
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
    } catch (_) {
      // API fallback
    }

    return CefrWord(
      word: word,
      cefrLevel: level.toUpperCase(),
      meaning: meaning.isNotEmpty ? meaning : 'คำแปล $word',
      partOfSpeech: partOfSpeech,
      exampleSentence: example.isNotEmpty
          ? example
          : 'Example sentence for $word.',
    );
  }
}
