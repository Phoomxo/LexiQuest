import 'package:flutter/material.dart';

enum MediaDependencyUnavailableReason { voice, speechPractice, objectScanner }

/// Typed fail-closed state for media routes whose runtime-owned dependency is
/// absent. No platform fallback is constructed by an individual screen.
final class MediaDependencyUnavailable extends StatelessWidget {
  const MediaDependencyUnavailable({super.key, required this.reason});

  final MediaDependencyUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    void chooseAlternative() {
      Navigator.maybePop(context);
    }

    return Scaffold(
      key: const ValueKey<String>('media-dependency-unavailable'),
      appBar: AppBar(title: const Text('การฝึกยังไม่พร้อมใช้งาน')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'กิจกรรมฝึกนี้ยังไม่พร้อมใช้งานบนอุปกรณ์นี้ '
                'ข้อมูลการเรียนที่บันทึกไว้ไม่เปลี่ยนแปลง',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                button: true,
                label: 'เลือกกิจกรรมที่ไม่ใช้เสียงหรือกล้อง',
                onTap: chooseAlternative,
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: chooseAlternative,
                    icon: const Icon(Icons.arrow_back_outlined),
                    label: const Text('เลือกกิจกรรมอื่น'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
