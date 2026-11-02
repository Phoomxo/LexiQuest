import '../domain/learning_pack.dart';

const bundledStarterCatalogId = 'lexiquest.starter.en-th.1';

final LearningPack bundledStarterPack = const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'lexiquest.starter.en-th',
      version: '1.0.0',
      title: 'แพ็กเริ่มต้น LexiQuest',
      objectives: const [
        'รู้จักคำใกล้ตัว 12 คำจากนิยามและตัวอย่าง',
        'ฝึกเลือกคำ พิมพ์ตอบ และทบทวนแฟลชการ์ด',
      ],
      cefrLevel: 'A1',
      language: 'en',
      meaningLanguage: 'th',
      provenance: const LearningPackProvenance(
        author: 'LexiQuest Team',
        source: 'Original AI-assisted English and Thai starter text',
        license: 'Proprietary. Subject to the LexiQuest LICENSE.',
        attribution:
            'Original AI-assisted text prepared for LexiQuest. Editorial review pending. '
            'A1 is an author-declared target, not a certified level. '
            'Copyright 2024-2026 Petch1910 / LexiQuest Team. All rights reserved.',
      ),
    ),
    entries: [
      LearningPackEntry(
        code: "cat",
        spelling: "cat",
        meaning: "แมว",
        partOfSpeech: "noun",
        definition: "A small animal that people keep as a pet and that meows.",
        examples: const [
          LearningPackExample(
            text: "The cat is under the chair.",
            translation: "แมวอยู่ใต้เก้าอี้",
          ),
        ],
        memoryCue: "นึกภาพแมวร้องเหมียวอยู่ใต้เก้าอี้",
        hint: "ชื่อสัตว์ที่ร้องเหมียว",
        strategy: "นึกภาพสัตว์ก่อนพูดคำศัพท์ แล้วลองแต่งประโยคของตนเอง",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/kæt/"),
        definitionQuestion: _question(
          0,
          "cat",
          "dog",
          "dog หมายถึงสุนัขซึ่งเห่า แต่นิยามนี้บอกว่าสัตว์ร้องเหมียว",
          "book",
          "book คือหนังสือ ไม่ใช่สัตว์เลี้ยง",
        ),
      ),
      LearningPackEntry(
        code: "dog",
        spelling: "dog",
        meaning: "สุนัข",
        partOfSpeech: "noun",
        definition: "An animal that people keep as a pet and that can bark.",
        examples: const [
          LearningPackExample(
            text: "The dog can run.",
            translation: "สุนัขวิ่งได้",
          ),
        ],
        memoryCue: "นึกภาพสุนัขวิ่งแล้วเห่า",
        hint: "ชื่อสัตว์ที่เห่า",
        strategy: "เปรียบเทียบเสียงของสัตว์สองชนิด แล้วพูดคำที่ตรงกับนิยาม",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/dɒɡ/"),
        definitionQuestion: _question(
          1,
          "dog",
          "cat",
          "cat หมายถึงแมวซึ่งร้องเหมียว แต่นิยามนี้บอกว่าสัตว์เห่า",
          "bus",
          "bus คือรถโดยสาร ไม่ใช่สัตว์เลี้ยง",
        ),
      ),
      LearningPackEntry(
        code: "book",
        spelling: "book",
        meaning: "หนังสือ",
        partOfSpeech: "noun",
        definition:
            "A set of pages with words or pictures, joined inside a cover.",
        examples: const [
          LearningPackExample(
            text: "I read a book.",
            translation: "ฉันอ่านหนังสือ",
          ),
        ],
        memoryCue: "นึกภาพหน้ากระดาษที่เปิดอ่านได้",
        hint: "สิ่งที่เราเปิดหน้าเพื่ออ่าน",
        strategy: "เชื่อมคำกับสิ่งของที่หยิบอ่านได้ แล้วลองบอกว่าชอบอ่านอะไร",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/bʊk/"),
        definitionQuestion: _question(
          2,
          "book",
          "home",
          "home คือสถานที่ที่อาศัยอยู่ ไม่ใช่สิ่งที่มีหน้ากระดาษให้เปิดอ่าน",
          "water",
          "water คือน้ำซึ่งเป็นของเหลว ไม่ใช่หน้ากระดาษในปก",
        ),
      ),
      LearningPackEntry(
        code: "water",
        spelling: "water",
        meaning: "น้ำ",
        partOfSpeech: "noun",
        definition: "A clear liquid that people drink.",
        examples: const [
          LearningPackExample(
            text: "I drink water.",
            translation: "ฉันดื่มน้ำ",
          ),
        ],
        memoryCue: "นึกภาพแก้วน้ำใส",
        hint: "ของเหลวใสที่เราดื่ม",
        strategy: "ใช้ท่าทางดื่มน้ำช่วยนึกคำ แล้วพูดประโยคสั้น ๆ",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/ˈwɔːtə/"),
        definitionQuestion: _question(
          0,
          "water",
          "cold",
          "cold บอกว่าอุณหภูมิต่ำ ไม่ใช่ชื่อของเหลวที่ดื่ม",
          "book",
          "book คือหนังสือ ไม่ใช่ของเหลว",
        ),
      ),
      LearningPackEntry(
        code: "bus",
        spelling: "bus",
        meaning: "รถโดยสาร",
        partOfSpeech: "noun",
        definition: "A large road vehicle that carries many passengers.",
        examples: const [
          LearningPackExample(
            text: "The bus stops here.",
            translation: "รถโดยสารจอดที่นี่",
          ),
        ],
        memoryCue: "นึกภาพรถคันใหญ่ที่มีผู้โดยสารหลายคน",
        hint: "ยานพาหนะบนถนนที่รับผู้โดยสารหลายคน",
        strategy: "นึกถึงการเดินทางประจำวัน แล้วเลือกคำที่ตรงกับยานพาหนะ",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/bʌs/"),
        definitionQuestion: _question(
          1,
          "bus",
          "home",
          "home คือสถานที่อยู่อาศัย ไม่ใช่ยานพาหนะที่วิ่งบนถนน",
          "dog",
          "dog คือสุนัข ไม่ใช่รถที่บรรทุกผู้โดยสาร",
        ),
      ),
      LearningPackEntry(
        code: "home",
        spelling: "home",
        meaning: "บ้าน",
        partOfSpeech: "noun",
        definition: "The place where someone lives.",
        examples: const [
          LearningPackExample(
            text: "I am at home.",
            translation: "ฉันอยู่ที่บ้าน",
          ),
        ],
        memoryCue: "นึกภาพสถานที่ที่ตนเองอาศัยอยู่",
        hint: "สถานที่ที่เราอาศัยอยู่",
        strategy: "นึกถึงบ้านของตนเอง แล้วพูดประโยคบอกว่าอยู่ที่ไหน",
        lexicalDetails: LearningPackLexicalDetails(ipa: "/həʊm/"),
        definitionQuestion: _question(
          2,
          "home",
          "bus",
          "bus เป็นยานพาหนะ นิยามนี้กล่าวถึงสถานที่ที่คนอาศัยอยู่",
          "book",
          "book คือหนังสือ ไม่ใช่สถานที่อยู่อาศัย",
        ),
      ),
      LearningPackEntry(
        code: "hot",
        spelling: "hot",
        meaning: "ร้อน",
        partOfSpeech: "adjective",
        definition: "Having a high temperature.",
        examples: const [
          LearningPackExample(text: "The soup is hot.", translation: "ซุปร้อน"),
        ],
        memoryCue: "นึกภาพไอที่ลอยจากซุป",
        hint: "อุณหภูมิสูง",
        strategy: "เปรียบเทียบร้อนกับเย็น แล้วใช้คำบอกอุณหภูมิของสิ่งใกล้ตัว",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/hɒt/",
          antonyms: const ["cold"],
        ),
        definitionQuestion: _question(
          0,
          "hot",
          "cold",
          "cold หมายถึงเย็นซึ่งมีอุณหภูมิต่ำ แต่นิยามนี้บอกว่าอุณหภูมิสูง",
          "open",
          "open ในแพ็กนี้หมายถึงเปิด ไม่ได้บอกอุณหภูมิ",
        ),
      ),
      LearningPackEntry(
        code: "cold",
        spelling: "cold",
        meaning: "เย็น",
        partOfSpeech: "adjective",
        definition: "Having a low temperature.",
        examples: const [
          LearningPackExample(
            text: "The water is cold.",
            translation: "น้ำเย็น",
          ),
        ],
        memoryCue: "นึกภาพน้ำเย็นในแก้ว",
        hint: "อุณหภูมิต่ำ",
        strategy: "จับคู่คำตรงข้าม แล้วบอกอุณหภูมิของน้ำในประโยค",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/kəʊld/",
          antonyms: const ["hot"],
        ),
        definitionQuestion: _question(
          1,
          "cold",
          "hot",
          "hot หมายถึงร้อนซึ่งมีอุณหภูมิสูง แต่นิยามนี้บอกว่าอุณหภูมิต่ำ",
          "water",
          "water เป็นชื่อน้ำ ไม่ใช่คำบอกอุณหภูมิ",
        ),
      ),
      LearningPackEntry(
        code: "open",
        spelling: "open",
        meaning: "เปิด",
        partOfSpeech: "verb",
        definition: "To move a door so that people can go through it.",
        examples: const [
          LearningPackExample(
            text: "Open the door, please.",
            translation: "กรุณาเปิดประตู",
          ),
        ],
        memoryCue: "นึกภาพประตูที่เปิดให้เดินผ่าน",
        hint: "ทำให้ประตูไม่ปิดอยู่",
        strategy: "ทำท่าทางเปิดประตู แล้วพูดคำสั่งสั้น ๆ",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/ˈəʊpən/",
          antonyms: const ["close"],
        ),
        definitionQuestion: _question(
          2,
          "open",
          "close",
          "close หมายถึงปิดประตู แต่นิยามนี้ต้องการให้คนเดินผ่านประตูได้",
          "day",
          "day คือช่วงเวลากลางวัน ไม่ใช่การขยับประตู",
        ),
      ),
      LearningPackEntry(
        code: "close",
        spelling: "close",
        meaning: "ปิด",
        partOfSpeech: "verb",
        definition: "To move a door so that people cannot go through it.",
        examples: const [
          LearningPackExample(
            text: "Close the window, please.",
            translation: "กรุณาปิดหน้าต่าง",
          ),
        ],
        memoryCue: "นึกภาพประตูที่ปิดทางเดิน",
        hint: "ทำให้ประตูไม่เปิดอยู่",
        strategy: "เปรียบเทียบท่าทางปิดกับเปิด แล้วพูดคำที่ตรงกับการกระทำ",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/kləʊz/",
          antonyms: const ["open"],
        ),
        definitionQuestion: _question(
          0,
          "close",
          "open",
          "open หมายถึงเปิดประตู แต่นิยามนี้ทำให้คนเดินผ่านไม่ได้",
          "night",
          "night คือช่วงเวลากลางคืน ไม่ใช่การขยับประตู",
        ),
      ),
      LearningPackEntry(
        code: "day",
        spelling: "day",
        meaning: "กลางวัน",
        partOfSpeech: "noun",
        definition: "The part of a day when there is light from the sun.",
        examples: const [
          LearningPackExample(
            text: "We play outside during the day.",
            translation: "พวกเราเล่นข้างนอกตอนกลางวัน",
          ),
        ],
        memoryCue: "นึกภาพแสงอาทิตย์ตอนออกไปเล่น",
        hint: "ช่วงเวลาที่มีแสงอาทิตย์",
        strategy: "จับคู่กลางวันกับกลางคืน แล้วบอกกิจกรรมในแต่ละช่วง",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/deɪ/",
          antonyms: const ["night"],
        ),
        definitionQuestion: _question(
          1,
          "day",
          "night",
          "night คือช่วงมืดตอนกลางคืน แต่นิยามนี้กล่าวถึงช่วงที่มีแสงอาทิตย์",
          "hot",
          "hot บอกอุณหภูมิร้อน ไม่ใช่ชื่อช่วงเวลา",
        ),
      ),
      LearningPackEntry(
        code: "night",
        spelling: "night",
        meaning: "กลางคืน",
        partOfSpeech: "noun",
        definition:
            "The dark part of a day when the sun is not seen in the sky.",
        examples: const [
          LearningPackExample(
            text: "I sleep at night.",
            translation: "ฉันนอนตอนกลางคืน",
          ),
        ],
        memoryCue: "นึกภาพท้องฟ้ามืดก่อนนอน",
        hint: "ช่วงเวลาที่ท้องฟ้ามืด",
        strategy: "นึกกิจวัตรก่อนนอน แล้วใช้คำบอกช่วงเวลาในประโยค",
        lexicalDetails: LearningPackLexicalDetails(
          ipa: "/naɪt/",
          antonyms: const ["day"],
        ),
        definitionQuestion: _question(
          2,
          "night",
          "day",
          "day ในแพ็กนี้คือช่วงมีแสงอาทิตย์ แต่นิยามนี้กล่าวถึงช่วงมืด",
          "cold",
          "cold บอกอุณหภูมิเย็น ไม่ใช่ชื่อช่วงเวลา",
        ),
      ),
    ],
  ),
);

LearningPackDefinitionQuestion _question(
  int correctPosition,
  String answer,
  String firstWrong,
  String firstExplanation,
  String secondWrong,
  String secondExplanation,
) {
  final options =
      [
        LearningPackDefinitionOption(
          code: 'first',
          entryCode: firstWrong,
          contrastiveExplanation: firstExplanation,
        ),
        LearningPackDefinitionOption(
          code: 'second',
          entryCode: secondWrong,
          contrastiveExplanation: secondExplanation,
        ),
      ]..insert(
        correctPosition,
        LearningPackDefinitionOption(code: 'answer', entryCode: answer),
      );
  return LearningPackDefinitionQuestion(
    correctOptionCode: 'answer',
    options: options,
  );
}
