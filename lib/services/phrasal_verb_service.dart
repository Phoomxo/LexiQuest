import '../models/phrasal_verb.dart';

class PhrasalVerbService {
  const PhrasalVerbService();

  static const List<PhrasalVerb> defaultPhrasalVerbs = [
    PhrasalVerb(
      phrase: 'look forward to',
      cefrLevel: 'B1',
      meaning: 'ตั้งหน้าตั้งตารอคอย',
      exampleSentence: 'I look forward to meeting you.',
    ),
    PhrasalVerb(
      phrase: 'give up',
      cefrLevel: 'A2',
      meaning: 'ยอมแพ้ / เลิกทำ',
      exampleSentence: 'Never give up on your dreams.',
    ),
    PhrasalVerb(
      phrase: 'come up with',
      cefrLevel: 'B2',
      meaning: 'คิดไอเดียออก',
      exampleSentence: 'She came up with a brilliant idea.',
    ),
    PhrasalVerb(
      phrase: 'bring about',
      cefrLevel: 'C1',
      meaning: 'ก่อให้เกิด / นำมาซึ่ง',
      exampleSentence: 'The new law brought about major changes.',
    ),
    PhrasalVerb(
      phrase: 'carry out',
      cefrLevel: 'B2',
      meaning: 'ดำเนินการให้สำเร็จ',
      exampleSentence: 'They carried out the experiment.',
    ),
  ];

  List<PhrasalVerb> getPhrasalVerbsByLevel(String level) {
    final normalized = level.trim().toUpperCase();
    return defaultPhrasalVerbs
        .where((pv) => pv.cefrLevel == normalized)
        .toList();
  }
}
