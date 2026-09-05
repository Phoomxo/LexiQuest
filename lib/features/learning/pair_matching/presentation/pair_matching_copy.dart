import 'package:flutter/widgets.dart';

/// Local, presentation-only copy for the Pair board.
final class PairMatchingCopy {
  const PairMatchingCopy._(this.english);

  factory PairMatchingCopy.forLocale(Locale locale) =>
      PairMatchingCopy._(locale.languageCode.toLowerCase() == 'en');

  final bool english;

  String choose(String thai, String englishText) =>
      english ? englishText : thai;

  String get title => choose('จับคู่คำ–ความหมาย', 'Match words and meanings');
  String get instruction => choose(
    'แตะคำและความหมายที่ตรงกัน',
    'Tap the word and its matching meaning',
  );
  String get chooseSource => choose('เลือกคำ', 'Choose a word');
  String get selectedSource => choose('คำที่เลือก', 'Selected word');
  String get chooseTarget => choose('เลือกความหมาย', 'Choose the meaning');
  String get choosePrompt =>
      choose('เลือกคำที่ตรงกัน', 'Choose the matching word');
  String get changeSource => choose('เลือกคำอื่น', 'Choose another word');
  String get revealMapping =>
      choose('ดูความหมาย (ใช้ตัวช่วย)', 'Show meaning (uses support)');
  String get confirmGuided => choose('ยืนยันคู่นี้', 'Confirm this pair');
  String get selectedState => choose('เลือกแล้ว', 'selected');
  String get readyAgainState =>
      choose('พร้อมลองอีกครั้ง', 'ready to try again');
  String get wrong => choose(
    'ยังไม่ใช่ ลองเก็บคำนี้ไว้แล้วกลับมาอีกครั้งนะ',
    'Not yet. Keep this word in mind and try it again shortly.',
  );
  String get repairQueued => choose(
    'คำนี้จะกลับมาหลังฝึกคำอื่นอีกสักครู่',
    'This word will return after a few other pairs.',
  );
  String get semanticHelp => choose(
    'ลองดูความหมายและฟังเสียง แล้วจับคู่อีกครั้ง',
    'Look at the meaning and listen, then match it again.',
  );
  String get guidedTail => choose(
    'ช่วยกันจับคู่คำนี้ให้ครบ แล้วระบบจะเก็บไว้ทบทวนอีกครั้ง',
    'Complete this pair with support. It will be saved for another review.',
  );
  String get audioUnavailable => choose(
    'ยังเล่นเสียงไม่ได้ ใช้ข้อความนี้แทน',
    'Audio is unavailable. Use this text instead',
  );
  String get timeoutReached =>
      choose('ถึงเวลาที่ตั้งไว้', 'Time target reached');
  String get continuedUntimed =>
      choose('ทำต่อโดยไม่จับเวลา', 'Continuing without a timer');

  String progress(int matched, int total) => choose(
    'จับคู่แล้ว $matched จาก $total คู่',
    'Matched $matched of $total pairs',
  );

  String timerRemaining(String clock) =>
      choose('เหลือ $clock', '$clock remaining');

  String languageName(String languageCode) => switch (languageCode) {
    'th' => choose('ภาษาไทย', 'Thai'),
    'en' => choose('ภาษาอังกฤษ', 'English'),
    _ => languageCode,
  };

  String tileLabel({
    required String languageCode,
    required String value,
    required bool selected,
    required bool repairAvailable,
  }) {
    final state = selected
        ? ', $selectedState'
        : repairAvailable
        ? ', $readyAgainState'
        : '';
    return choose(
      'คำ${languageName(languageCode)} $value$state',
      '${languageName(languageCode)} word $value$state',
    );
  }

  String pronounce(String languageCode) => switch (languageCode) {
    'th' => choose('ฟังคำไทย', 'Listen to Thai word'),
    'en' => choose('ฟังคำอังกฤษ', 'Listen to English word'),
    _ => choose('ฟังคำ $languageCode', 'Listen to $languageCode word'),
  };
}
