import 'package:flutter/material.dart';

import '../features/consent/application/research_consent_use_cases.dart';

Future<bool?> showResearchConsentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: AlertDialog(
          title: const Text('เลือกเข้าร่วมการวิจัย'),
          content: const SingleChildScrollView(
            child: Text(
              'LexiQuest จะบันทึกกิจกรรมการเรียน คำตอบ คะแนน ความคืบหน้า '
              'ข้อมูลประสิทธิภาพอุปกรณ์ และข้อผิดพลาดที่ไม่รวมรหัสเชื่อมต่อบริการ AI (API key) '
              'หรือเสียงดิบ เพื่อประเมินระบบรุ่นทดลอง\n\n'
              'การเข้าร่วมเป็นความสมัครใจ ถอนความยินยอมได้จากหน้าตั้งค่า '
              'การเลือกยังไม่ยินยอมจะไม่ปิดการเรียนแบบออฟไลน์ '
              'และข้อมูลจะไม่ถูกส่งออกเป็นชุดวิจัย'
              'หากไม่มีความยินยอมที่ยังมีผล\n\n'
              'รอบทดลองใช้เวลา 30 วัน ข้อมูลวิจัยใช้นามแฝงและเก็บไม่เกิน '
              '180 วัน ข้อมูลอยู่ในเครื่องก่อนและจะส่งไป Cloud เฉพาะเมื่อ '
              'คุณใช้บัญชีและระบบ Cloud ได้รับอนุมัติ ความเสี่ยงที่เหลือรวมถึง '
              'ค่าอินเทอร์เน็ต การสูญหายเมื่อลบแอปก่อนซิงก์ และการประมวลผล '
              'โดยผู้ให้บริการที่คุณเลือกใช้\n\n'
              'ดูผู้ควบคุมข้อมูล ช่องทางติดต่อ และวิธีขอลบข้อมูลในประกาศฉบับเต็ม: '
              'https://vocab-learning-app-219ef.web.app/privacy/\n\n'
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
      ),
    ),
  );
}
