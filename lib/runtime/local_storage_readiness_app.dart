import 'package:flutter/material.dart';
import '../data/local/app_database_open_policy.dart';

/// A failed storage preflight must not leave the user on an empty launch screen.
final class LocalStorageReadinessApp extends StatelessWidget {
  const LocalStorageReadinessApp({super.key, required this.failure});
  final AppDatabaseOpenException failure;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ยังเปิดข้อมูลการเรียนไม่ได้',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),
                Text(switch (failure.code) {
                  AppDatabaseOpenError.incompatibleSchema =>
                    'รูปแบบฐานข้อมูลไม่รองรับในแอปเวอร์ชันนี้ โปรดใช้เวอร์ชันที่รองรับข้อมูลนี้',
                  AppDatabaseOpenError.corruptOrUnreadable =>
                    'อ่านหรือตรวจสอบฐานข้อมูลไม่สำเร็จ โปรดตรวจสิทธิ์เข้าถึงหรือกู้คืนจากข้อมูลสำรอง',
                  AppDatabaseOpenError.legacyImportRequired =>
                    'พบฐานข้อมูลการเรียนรุ่นเดิม ต้องนำเข้าด้วยเครื่องมือที่รองรับก่อนเริ่มใช้งาน',
                }),
                const SizedBox(height: 16),
                const Text('แอปไม่ได้ลบหรือรีเซ็ตไฟล์ข้อมูลของคุณ'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
