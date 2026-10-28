import 'package:flutter/material.dart';

import '../features/consent/application/research_consent_use_cases.dart';

Future<bool> showResearchConsentDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ความยินยอมเข้าร่วมการทดลอง'),
      content: const SingleChildScrollView(
        child: Text(
          'LexiQuest จะบันทึกกิจกรรมการเรียน คำตอบ คะแนน ความคืบหน้า '
          'ข้อมูลประสิทธิภาพอุปกรณ์ และข้อผิดพลาดที่ไม่รวม API key '
          'หรือเสียงดิบ เพื่อประเมินระบบรุ่นทดลอง\n\n'
          'การเข้าร่วมเป็นความสมัครใจ ถอนความยินยอมได้จากหน้าตั้งค่า '
          'การเลือกยังไม่ยินยอมจะไม่ปิดการเรียนแบบออฟไลน์ '
          'และข้อมูลจะไม่ถูกส่งออกเป็นชุดวิจัย'
          'หากไม่มีความยินยอมที่ยังมีผล\n\n'
          'ฉบับความยินยอม: '
          '${ResearchConsentUseCases.currentVersion}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('ยังไม่ยินยอม'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('ยินยอมเข้าร่วม'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
