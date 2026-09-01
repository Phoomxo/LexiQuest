import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  test(
    'Thai navigation glossary matches the exact approved entry contract',
    () {
      expect(
        NavigationGlossary.entries.keys.toSet(),
        _expectedEntries.keys.toSet(),
      );
      for (final MapEntry(key: id, value: expected)
          in _expectedEntries.entries) {
        final actual = NavigationGlossary.require(id);
        expect(actual.id, id, reason: '$id must retain its map identity');
        expect(actual.fullThaiLabel, expected.full, reason: '$id full label');
        expect(
          actual.shortThaiLabel,
          expected.short,
          reason: '$id short label',
        );
        expect(
          actual.semanticsLabel,
          expected.semantics,
          reason: '$id semantics label',
        );
        expect(actual.tooltip, expected.tooltip, reason: '$id tooltip');
        expect(actual.icon, expected.icon, reason: '$id icon');
        expect(
          actual.selectedIcon,
          expected.selectedIcon,
          reason: '$id selected icon',
        );
      }
    },
  );

  test('missing registered identity fails closed without a label fallback', () {
    expect(
      () => NavigationGlossary.require('home/not-registered'),
      throwsA(isA<StateError>()),
    );
  });
}

final class _ExpectedEntry {
  const _ExpectedEntry(
    this.full,
    this.short,
    this.semantics,
    this.tooltip,
    this.icon, [
    this.selectedIcon,
  ]);

  final String full;
  final String short;
  final String semantics;
  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
}

const _expectedEntries = <String, _ExpectedEntry>{
  'home/vocabulary': _ExpectedEntry(
    'คลังคำศัพท์',
    'คลังคำศัพท์',
    'เปิดคลังคำศัพท์',
    'เปิดคลังคำศัพท์',
    Icons.menu_book_outlined,
    Icons.menu_book,
  ),
  'home/learn': _ExpectedEntry(
    'การเรียนรู้',
    'การเรียนรู้',
    'เปิดการเรียนรู้',
    'เปิดกิจกรรมการเรียนรู้',
    Icons.school_outlined,
    Icons.school,
  ),
  'home/today': _ExpectedEntry(
    'วันนี้',
    'วันนี้',
    'เปิดกิจกรรมวันนี้',
    'เปิดกิจกรรมวันนี้',
    Icons.today_outlined,
    Icons.today,
  ),
  'home/study-planning': _ExpectedEntry(
    'วางแผนการเรียน',
    'วางแผน',
    'เปิดวางแผนการเรียน',
    'เปิดวางแผนการเรียน',
    Icons.event_note_outlined,
    Icons.event_note,
  ),
  'home/mastery': _ExpectedEntry(
    'ความชำนาญ',
    'ความชำนาญ',
    'เปิดภาพรวมความชำนาญ',
    'เปิดภาพรวมความชำนาญ',
    Icons.analytics_outlined,
    Icons.analytics,
  ),
  'home/weakness': _ExpectedEntry(
    'จุดที่ควรฝึกเพิ่ม',
    'ฝึกเพิ่ม',
    'เปิดจุดที่ควรฝึกเพิ่ม',
    'เปิดจุดที่ควรฝึกเพิ่ม',
    Icons.healing_outlined,
    Icons.healing,
  ),
  'home/achievements': _ExpectedEntry(
    'รางวัล',
    'รางวัล',
    'เปิดรางวัล',
    'เปิดรางวัล',
    Icons.emoji_events_outlined,
    Icons.emoji_events,
  ),
  'home/profile': _ExpectedEntry(
    'โปรไฟล์',
    'โปรไฟล์',
    'เปิดโปรไฟล์',
    'เปิดโปรไฟล์',
    Icons.person_outlined,
    Icons.person,
  ),
  'drawer/rewards/shop': _ExpectedEntry(
    'ร้านค้า',
    'ร้านค้า',
    'เปิดร้านค้า',
    'เปิดร้านค้า',
    Icons.shopping_bag,
  ),
  'drawer/practice/object-scanner': _ExpectedEntry(
    'สแกนวัตถุ',
    'สแกนวัตถุ',
    'เปิดสแกนวัตถุ',
    'เปิดสแกนวัตถุ',
    Icons.document_scanner_outlined,
  ),
  'drawer/practice/shadowing': _ExpectedEntry(
    'ฝึกพูดตามเสียง',
    'ฝึกพูดตามเสียง',
    'เปิดฝึกพูดตามเสียง',
    'เปิดฝึกพูดตามเสียง',
    Icons.mic_none,
  ),
  'drawer/learning/ghost-duel': _ExpectedEntry(
    'ดวลกับสถิติเดิม',
    'ดวลกับสถิติเดิม',
    'เปิดดวลกับสถิติเดิม',
    'เปิดกิจกรรมเปรียบเทียบกับสถิติเดิม',
    Icons.sports_esports_outlined,
  ),
  'drawer/ai-tutor/chat': _ExpectedEntry(
    'ผู้ช่วยสอน AI',
    'ผู้ช่วยสอน AI',
    'เปิดผู้ช่วยสอน AI',
    'เปิดผู้ช่วยสอน AI',
    Icons.chat_bubble_outline,
  ),
  'drawer/ai-tutor/settings': _ExpectedEntry(
    'ตั้งค่าการเชื่อมต่อ AI',
    'ตั้งค่า AI',
    'เปิดตั้งค่าการเชื่อมต่อ AI',
    'จัดการกุญแจส่วนตัวที่เก็บในเครื่อง',
    Icons.key_outlined,
  ),
  'drawer/export/center': _ExpectedEntry(
    'ส่งออกข้อมูล',
    'ส่งออกข้อมูล',
    'เปิดการส่งออกข้อมูล',
    'เปิดการส่งออกข้อมูล',
    Icons.file_download_outlined,
  ),
  'drawer/rewards/quests': _ExpectedEntry(
    'ภารกิจการเรียน',
    'ภารกิจ',
    'เปิดภารกิจการเรียน',
    'เปิดภารกิจการเรียน',
    Icons.flag_outlined,
  ),
  'drawer/settings': _ExpectedEntry(
    'ตั้งค่า',
    'ตั้งค่า',
    'เปิดการตั้งค่า',
    'เปิดการตั้งค่า',
    Icons.settings,
  ),
  'home/learn/associative-reading': _ExpectedEntry(
    'อ่านเชื่อมโยงความจำ',
    'อ่านเชื่อมโยงความจำ',
    'เปิดอ่านเชื่อมโยงความจำ',
    'สร้างเรื่องเชื่อมโยงคำศัพท์เพื่อช่วยจำ',
    Icons.auto_stories_outlined,
  ),
  'home/learn/quiz': _ExpectedEntry(
    'แบบทดสอบจากคลังคำศัพท์',
    'แบบทดสอบ',
    'เปิดแบบทดสอบจากคลังคำศัพท์',
    'ตอบความหมายจากคำศัพท์ที่บันทึกไว้',
    Icons.quiz_outlined,
  ),
  'home/learn/quiz/typed-recall': _ExpectedEntry(
    'นึกคำแล้วพิมพ์',
    'นึกคำแล้วพิมพ์',
    'เปิดกิจกรรมนึกคำแล้วพิมพ์',
    'นึกตัวสะกดจากความจำแล้วพิมพ์คำตอบ',
    Icons.keyboard_outlined,
  ),
  'home/learn/quiz/matching': _ExpectedEntry(
    'จับคู่คำศัพท์',
    'จับคู่คำศัพท์',
    'เปิดกิจกรรมจับคู่คำศัพท์',
    'จับคู่คำศัพท์กับความหมาย',
    Icons.compare_arrows_outlined,
  ),
  'home/learn/quiz/cloze': _ExpectedEntry(
    'เติมคำในประโยค',
    'เติมคำในประโยค',
    'เปิดกิจกรรมเติมคำในประโยค',
    'เลือกหรือพิมพ์คำลงในประโยคที่ตรวจทานแล้ว',
    Icons.space_bar_outlined,
  ),
  'home/learn/quiz/definition': _ExpectedEntry(
    'เลือกคำจากคำอธิบาย',
    'เลือกคำจากคำอธิบาย',
    'เปิดกิจกรรมเลือกคำจากคำอธิบาย',
    'เลือกคำศัพท์จากคำอธิบายที่ตรวจทานแล้ว',
    Icons.menu_book_outlined,
  ),
  'home/learn/srs': _ExpectedEntry(
    'ทบทวนแบบเว้นระยะ (SRS)',
    'ทบทวน (SRS)',
    'เปิดทบทวนแบบเว้นระยะ SRS',
    'ทบทวนคำศัพท์ตามกำหนดจากประวัติคำตอบ',
    Icons.event_repeat_outlined,
  ),
  'home/learn/reading/cefr': _ExpectedEntry(
    'อ่านตามระดับภาษา CEFR',
    'อ่าน CEFR',
    'เปิดอ่านตามระดับภาษา CEFR',
    'อ่านบทความตามระดับภาษา CEFR',
    Icons.chrome_reader_mode_outlined,
  ),
  'home/learn/quiz/dictation': _ExpectedEntry(
    'ฟังแล้วพิมพ์',
    'ฟังแล้วพิมพ์',
    'เปิดกิจกรรมฟังแล้วพิมพ์',
    'ฟังเสียงแล้วพิมพ์คำศัพท์',
    Icons.hearing_outlined,
  ),
  'home/learn/quiz/sentence-scramble': _ExpectedEntry(
    'เรียงประโยค',
    'เรียงประโยค',
    'เปิดกิจกรรมเรียงประโยค',
    'เรียงคำให้เป็นประโยคที่ถูกต้อง',
    Icons.format_list_numbered_outlined,
  ),
  'home/learn/quiz/word-scramble': _ExpectedEntry(
    'เรียงตัวอักษร',
    'เรียงตัวอักษร',
    'เปิดกิจกรรมเรียงตัวอักษร',
    'เรียงตัวอักษรให้เป็นคำศัพท์',
    Icons.extension_outlined,
  ),
  'home/learn/speech/speaking': _ExpectedEntry(
    'ฝึกออกเสียง',
    'ฝึกออกเสียง',
    'เปิดกิจกรรมฝึกออกเสียง',
    'ฝึกออกเสียงด้วยการรู้จำเสียงบนอุปกรณ์',
    Icons.mic_outlined,
  ),
  'home/learn/speech/shadowing': _ExpectedEntry(
    'ฝึกพูดตามเสียง',
    'ฝึกพูดตามเสียง',
    'เปิดกิจกรรมฝึกพูดตามเสียง',
    'ฟังตัวอย่างแล้วฝึกพูดตาม',
    Icons.record_voice_over_outlined,
  ),
  'today-hub-resume-action': _ExpectedEntry(
    'เรียนต่อ',
    'เรียนต่อ',
    'เรียนต่อจากกิจกรรมเดิม',
    'เรียนต่อจากกิจกรรมเดิม',
    Icons.play_arrow,
  ),
  'today-hub-start-recommendation': _ExpectedEntry(
    'เริ่มกิจกรรมที่แนะนำ',
    'เริ่มกิจกรรมที่แนะนำ',
    'เริ่มกิจกรรมที่แนะนำ',
    'เริ่มกิจกรรมที่แนะนำสำหรับวันนี้',
    Icons.auto_awesome_outlined,
  ),
  'today-hub-assessment-action': _ExpectedEntry(
    'เริ่มแบบประเมิน',
    'เริ่มแบบประเมิน',
    'เริ่มแบบประเมินที่ได้รับมอบหมาย',
    'เริ่มแบบประเมินที่ได้รับมอบหมาย',
    Icons.assignment_outlined,
  ),
  'today-hub-open-review': _ExpectedEntry(
    'เปิดศูนย์ทบทวน',
    'เปิดศูนย์ทบทวน',
    'เปิดศูนย์ทบทวน',
    'เปิดศูนย์ทบทวน',
    Icons.fact_check_outlined,
  ),
  'today-hub-open-history': _ExpectedEntry(
    'ดูประวัติการเรียน',
    'ดูประวัติการเรียน',
    'เปิดประวัติการเรียน',
    'เปิดประวัติการเรียน',
    Icons.history,
  ),
  'study-planning/open-catalog': _ExpectedEntry(
    'เลือกชุดเนื้อหาการเรียน',
    'เลือกชุดเนื้อหา',
    'เปิดชุดเนื้อหาการเรียนที่ตรวจสอบแล้ว',
    'เปิดชุดเนื้อหาการเรียนที่ตรวจสอบแล้ว',
    Icons.menu_book_outlined,
  ),
  'study-planning/open-goals': _ExpectedEntry(
    'เป้าหมายการเรียน',
    'เป้าหมายการเรียน',
    'เปิดเป้าหมายการเรียน',
    'เปิดเป้าหมายการเรียน',
    Icons.flag_outlined,
  ),
  'study-planning/open-learning-preferences': _ExpectedEntry(
    'การตั้งค่าการเรียน',
    'การตั้งค่าการเรียน',
    'เปิดการตั้งค่าการเรียน',
    'เปิดการตั้งค่าการเรียน',
    Icons.tune_outlined,
  ),
  'settings/display': _ExpectedEntry(
    'การแสดงผล',
    'การแสดงผล',
    'การตั้งค่าการแสดงผล',
    'การตั้งค่าการแสดงผล',
    Icons.display_settings_outlined,
  ),
  'theme-system': _ExpectedEntry(
    'ระบบ',
    'ระบบ',
    'ใช้รูปแบบตามระบบ',
    'ใช้รูปแบบตามระบบ',
    Icons.settings_suggest_outlined,
  ),
  'theme-light': _ExpectedEntry(
    'สว่าง',
    'สว่าง',
    'ใช้รูปแบบสว่าง',
    'ใช้รูปแบบสว่าง',
    Icons.light_mode_outlined,
  ),
  'theme-dark': _ExpectedEntry(
    'มืด',
    'มืด',
    'ใช้รูปแบบมืด',
    'ใช้รูปแบบมืด',
    Icons.dark_mode_outlined,
  ),
  'reduced-motion-switch': _ExpectedEntry(
    'ลดการเคลื่อนไหว',
    'ลดการเคลื่อนไหว',
    'เปิดหรือปิดการลดการเคลื่อนไหว',
    'เปิดหรือปิดการลดการเคลื่อนไหว',
    Icons.motion_photos_off_outlined,
  ),
  'settings/account': _ExpectedEntry(
    'บัญชีผู้ใช้',
    'บัญชีผู้ใช้',
    'ข้อมูลบัญชีผู้ใช้',
    'ข้อมูลบัญชีผู้ใช้',
    Icons.person_outline,
  ),
  'settings/offline-content': _ExpectedEntry(
    'เนื้อหาออฟไลน์',
    'เนื้อหาออฟไลน์',
    'เปิดการจัดการเนื้อหาออฟไลน์',
    'เปิดการจัดการเนื้อหาออฟไลน์',
    Icons.offline_pin_outlined,
  ),
  'settings/research-consent': _ExpectedEntry(
    'ความยินยอมงานวิจัย',
    'ความยินยอมงานวิจัย',
    'จัดการความยินยอมงานวิจัย',
    'จัดการความยินยอมงานวิจัย',
    Icons.fact_check_outlined,
  ),
  'settings/cloud-status': _ExpectedEntry(
    'สถานะการเชื่อมต่อระบบออนไลน์',
    'สถานะออนไลน์',
    'ตรวจสอบสถานะการเชื่อมต่อระบบออนไลน์',
    'ตรวจสอบสถานะการเชื่อมต่อระบบออนไลน์',
    Icons.cloud_done_outlined,
  ),
  'settings/change-password': _ExpectedEntry(
    'เปลี่ยนรหัสผ่าน',
    'เปลี่ยนรหัสผ่าน',
    'เปิดการเปลี่ยนรหัสผ่าน',
    'เปิดการเปลี่ยนรหัสผ่าน',
    Icons.password_outlined,
  ),
  'settings/logout': _ExpectedEntry(
    'ออกจากระบบ',
    'ออกจากระบบ',
    'ออกจากระบบ',
    'ออกจากระบบ',
    Icons.logout,
  ),
  'erase-local-data': _ExpectedEntry(
    'ลบข้อมูลในเครื่องทั้งหมด',
    'ลบข้อมูลในเครื่องทั้งหมด',
    'ลบข้อมูลในเครื่องทั้งหมด',
    'ลบคำศัพท์ ประวัติการเรียน ความยินยอม และกุญแจ AI ที่บันทึกในเครื่อง',
    Icons.delete_forever_outlined,
  ),
  'profile/mastery': _ExpectedEntry(
    'ความชำนาญ',
    'ความชำนาญ',
    'ความชำนาญ',
    'ความชำนาญ',
    Icons.analytics_outlined,
  ),
  'profile/srs': _ExpectedEntry(
    'ทบทวนแบบเว้นระยะ (SRS)',
    'ทบทวน (SRS)',
    'สถานะการทบทวนแบบเว้นระยะ SRS',
    'สถานะการทบทวนแบบเว้นระยะ SRS',
    Icons.event_repeat_outlined,
  ),
  'profile/effort': _ExpectedEntry(
    'เวลาเรียนจริง',
    'เวลาเรียนจริง',
    'เวลาเรียนจริง',
    'เวลาเรียนจริง',
    Icons.timer_outlined,
  ),
  'profile/accuracy': _ExpectedEntry(
    'ความแม่นยำ',
    'ความแม่นยำ',
    'ความแม่นยำ',
    'ความแม่นยำ',
    Icons.check_circle_outline,
  ),
  'profile/weakness': _ExpectedEntry(
    'จุดที่ควรฝึกเพิ่ม',
    'จุดที่ควรฝึกเพิ่ม',
    'จุดที่ควรฝึกเพิ่ม',
    'จุดที่ควรฝึกเพิ่ม',
    Icons.healing_outlined,
  ),
  'profile/engagement': _ExpectedEntry(
    'ความต่อเนื่องในการเรียน',
    'ความต่อเนื่องในการเรียน',
    'ความต่อเนื่องในการเรียน',
    'ความต่อเนื่องในการเรียน',
    Icons.local_fire_department_outlined,
  ),
  'home/today/review': _ExpectedEntry(
    'ศูนย์ทบทวน',
    'ศูนย์ทบทวน',
    'ศูนย์ทบทวน',
    'ศูนย์ทบทวน',
    Icons.fact_check_outlined,
  ),
  'home/today/history': _ExpectedEntry(
    'ประวัติการเรียน',
    'ประวัติการเรียน',
    'ประวัติการเรียน',
    'ประวัติการเรียน',
    Icons.history,
  ),
  'research/assessment': _ExpectedEntry(
    'แบบประเมิน',
    'แบบประเมิน',
    'แบบประเมินที่ได้รับมอบหมาย',
    'แบบประเมินที่ได้รับมอบหมาย',
    Icons.assignment_outlined,
  ),
  'study-planning/catalog': _ExpectedEntry(
    'ชุดเนื้อหาการเรียน',
    'ชุดเนื้อหาการเรียน',
    'ชุดเนื้อหาการเรียน',
    'ชุดเนื้อหาการเรียน',
    Icons.menu_book_outlined,
  ),
  'study-planning/goals': _ExpectedEntry(
    'เป้าหมายการเรียน',
    'เป้าหมายการเรียน',
    'เป้าหมายการเรียน',
    'เป้าหมายการเรียน',
    Icons.flag_outlined,
  ),
  'study-planning/learning-preferences': _ExpectedEntry(
    'การตั้งค่าการเรียน',
    'การตั้งค่าการเรียน',
    'การตั้งค่าการเรียน',
    'การตั้งค่าการเรียน',
    Icons.tune_outlined,
  ),
};
