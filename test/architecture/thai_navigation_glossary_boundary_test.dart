import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  test(
    'registered Latin acronyms are allowed only in exact canonical fields',
    () {
      final latin = RegExp(r'[A-Za-z]');
      for (final entry in NavigationGlossary.entries.values) {
        final fields = <String, String>{
          'fullThaiLabel': entry.fullThaiLabel,
          'shortThaiLabel': entry.shortThaiLabel,
          'semanticsLabel': entry.semanticsLabel,
          'tooltip': entry.tooltip,
        };
        for (final MapEntry(key: field, value: value) in fields.entries) {
          final expected = _approvedLatinFields[(entry.id, field)];
          if (expected == null) {
            expect(
              latin.hasMatch(value),
              isFalse,
              reason: '${entry.id}.$field: $value',
            );
          } else {
            expect(value, expected, reason: '${entry.id}.$field');
          }
        }
      }
    },
  );

  test('approved acronyms retain canonical Thai explanatory context', () {
    expect(
      NavigationGlossary.require('drawer/ai-tutor/chat').fullThaiLabel,
      'ผู้ช่วยสอน AI',
    );
    expect(
      NavigationGlossary.require('home/learn/srs').fullThaiLabel,
      'ทบทวนแบบเว้นระยะ (SRS)',
    );
    expect(
      NavigationGlossary.require('home/learn/reading/cefr').fullThaiLabel,
      'อ่านตามระดับภาษา CEFR',
    );
  });
}

const _approvedLatinFields = <(String, String), String>{
  ('drawer/ai-tutor/chat', 'fullThaiLabel'): 'ผู้ช่วยสอน AI',
  ('drawer/ai-tutor/chat', 'shortThaiLabel'): 'ผู้ช่วยสอน AI',
  ('drawer/ai-tutor/chat', 'semanticsLabel'): 'เปิดผู้ช่วยสอน AI',
  ('drawer/ai-tutor/chat', 'tooltip'): 'เปิดผู้ช่วยสอน AI',
  ('drawer/ai-tutor/settings', 'fullThaiLabel'): 'ตั้งค่าการเชื่อมต่อ AI',
  ('drawer/ai-tutor/settings', 'shortThaiLabel'): 'ตั้งค่า AI',
  ('drawer/ai-tutor/settings', 'semanticsLabel'): 'เปิดตั้งค่าการเชื่อมต่อ AI',
  ('erase-local-data', 'tooltip'):
      'ลบคำศัพท์ ประวัติการเรียน ความยินยอม และกุญแจ AI ที่บันทึกในเครื่อง',
  ('home/learn/srs', 'fullThaiLabel'): 'ทบทวนแบบเว้นระยะ (SRS)',
  ('home/learn/srs', 'shortThaiLabel'): 'ทบทวน (SRS)',
  ('home/learn/srs', 'semanticsLabel'): 'เปิดทบทวนแบบเว้นระยะ SRS',
  ('home/learn/reading/cefr', 'fullThaiLabel'): 'อ่านตามระดับภาษา CEFR',
  ('home/learn/reading/cefr', 'shortThaiLabel'): 'อ่าน CEFR',
  ('home/learn/reading/cefr', 'semanticsLabel'): 'เปิดอ่านตามระดับภาษา CEFR',
  ('home/learn/reading/cefr', 'tooltip'): 'อ่านบทความตามระดับภาษา CEFR',
  ('profile/srs', 'fullThaiLabel'): 'ทบทวนแบบเว้นระยะ (SRS)',
  ('profile/srs', 'shortThaiLabel'): 'ทบทวน (SRS)',
  ('profile/srs', 'semanticsLabel'): 'สถานะการทบทวนแบบเว้นระยะ SRS',
  ('profile/srs', 'tooltip'): 'สถานะการทบทวนแบบเว้นระยะ SRS',
};
