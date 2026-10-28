import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Original starter sentences, explicitly reviewed against these alternatives.
/// Source/AI-assisted engineering review, 2026-09-20; no CEFR/efficacy claim.
final class ContextPracticeInventory {
  const ContextPracticeInventory();

  static const revision = 1;
  static const entries = <ContextPracticeEntry>[
    ContextPracticeEntry(
      'book',
      'a92b4c2e6a8db6c1b760b82ee7bc8341afcd26b974bba78a06c0385696731bee',
      'I read a book with fifty pages.',
      'read a book',
      'pencil',
      'book คือหนังสือที่มีหลายหน้า ใช้กับ read ในบริบทนี้',
      'pencil เป็นเครื่องเขียน ไม่ใช่สิ่งที่มีห้าสิบหน้าให้อ่าน',
    ),
    ContextPracticeEntry(
      'pencil',
      '5c2c96810f0b52bcafcafb31cc418382dfc9ae5a2be4326878f25285625dfbca',
      'I write with a pencil and erase a wrong letter.',
      'write with a pencil',
      'book',
      'pencil ใช้เขียนและลบรอยตัวอักษรได้ สอดคล้องกับ write with และ erase',
      'book เป็นสิ่งที่อ่าน ไม่ใช่เครื่องมือที่ใช้เขียนและลบรอย',
    ),
    ContextPracticeEntry(
      'bottle',
      '61dd55ca6b4a3574e304be3738befba59b9a5c1ba17993ef411db189b713c562',
      'I pour water from a bottle with a narrow neck.',
      'pour water from a bottle',
      'cup',
      'bottle คือขวด คำใบ้ narrow neck บอกว่าภาชนะมีคอแคบ',
      'cup คือถ้วยปากเปิด จึงไม่ตรงกับลักษณะคอแคบของขวดในประโยคนี้',
    ),
  ];

  static String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'revision': revision,
            'entries': [for (final e in entries) e.toJson()],
          }),
        ),
      )
      .toString();

  ContextPracticeEntry? find(String wordId) {
    for (final entry in entries) {
      if (entry.wordId == wordId) return entry;
    }
    return null;
  }

  bool admits({
    required String wordId,
    required String artifactHash,
    required String sentence,
    required List<String> options,
  }) {
    final entry = find(wordId);
    return entry != null &&
        artifactHash == entry.artifactHash &&
        sentence == entry.sentence &&
        options.length == 2 &&
        options.toSet().length == 2 &&
        options.contains(entry.answer) &&
        options.contains(entry.distractor);
  }
}

final class ContextPracticeEntry {
  const ContextPracticeEntry(
    this.answer,
    this.artifactHash,
    this.sentence,
    this.collocation,
    this.distractor,
    this.correctRationale,
    this.distractorRationale,
  );
  final String answer, artifactHash, sentence, collocation, distractor;
  final String correctRationale, distractorRationale;
  String get wordId => 'word:starter-$answer';
  String get distractorId => 'word:starter-$distractor';
  String get distractorArtifactHash => switch (distractor) {
    'book' =>
      'a92b4c2e6a8db6c1b760b82ee7bc8341afcd26b974bba78a06c0385696731bee',
    'pencil' =>
      '5c2c96810f0b52bcafcafb31cc418382dfc9ae5a2be4326878f25285625dfbca',
    'cup' => '4af13e68ae9dc7364560bb9cd15e40c5e0fb1a43d16b8f46ea8f8376adf1cc38',
    _ => throw StateError('Unreviewed context alternative'),
  };
  Map<String, Object?> toJson() => {
    'wordId': wordId,
    'artifactHash': artifactHash,
    'sentence': sentence,
    'collocation': collocation,
    'distractorId': distractorId,
    'distractorArtifactHash': distractorArtifactHash,
    'correctRationale': correctRationale,
    'distractorRationale': distractorRationale,
  };
}
