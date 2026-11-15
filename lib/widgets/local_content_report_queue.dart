import 'package:flutter/material.dart';

import '../features/vocabulary/domain/local_content_report.dart';

class LocalContentReportQueue extends StatelessWidget {
  const LocalContentReportQueue({super.key, required this.reports});

  final Stream<List<LocalContentReportDraft>> reports;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: reports,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('อ่านรายงานในเครื่องไม่สำเร็จ'));
      }
      if (!snapshot.hasData) {
        return const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'กำลังอ่านรายงานในเครื่อง',
          ),
        );
      }
      final rows = snapshot.requireData;
      return ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: rows.isEmpty ? 2 : rows.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('ออฟไลน์ · เก็บในเครื่อง'),
            );
          }
          if (index == 1) {
            return Text(
              rows.isEmpty ? 'ยังไม่มีรายงาน' : 'ยังไม่ส่งถึงผู้จัดทำ',
            );
          }
          final report = rows[index - 2];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${report.spelling} · ${report.meaning}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localContentReportReasonLabel(report.reason)),
                if (report.sentence case final sentence?) Text(sentence),
              ],
            ),
          );
        },
      );
    },
  );
}

String localContentReportReasonLabel(LocalContentReportReason reason) =>
    switch (reason) {
      LocalContentReportReason.translationMismatch => 'คำแปลไม่ตรง',
      LocalContentReportReason.exampleSpellingError => 'ประโยคตัวอย่างสะกดผิด',
    };
