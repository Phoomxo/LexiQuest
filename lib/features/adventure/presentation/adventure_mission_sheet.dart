import 'package:flutter/material.dart';

import '../domain/adventure_journey.dart';

final class AdventureMissionSheet extends StatefulWidget {
  const AdventureMissionSheet({
    super.key,
    required this.mission,
    required this.onStart,
    this.onStartDialogue,
  });

  final AdventureMissionRef? mission;
  final Future<void> Function(AdventureMissionRef mission) onStart;
  final Future<void> Function(AdventureMissionRef mission)? onStartDialogue;

  @override
  State<AdventureMissionSheet> createState() => _AdventureMissionSheetState();
}

final class _AdventureMissionSheetState extends State<AdventureMissionSheet> {
  var _starting = false;

  Future<void> _start({bool dialogue = false}) async {
    final mission = widget.mission;
    if (mission == null || _starting) return;
    setState(() => _starting = true);
    try {
      await (dialogue ? widget.onStartDialogue! : widget.onStart)(mission);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปิดภารกิจไม่สำเร็จ ลองใหม่ได้เมื่อพร้อม'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mission = widget.mission;
    return Card(
      key: const ValueKey('adventure-primary-mission'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              mission == null ? 'ยังไม่มีภารกิจหลัก' : 'ภารกิจหลักวันนี้',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              mission == null
                  ? 'พักได้ แล้วกลับมาใหม่เมื่อพร้อม'
                  : _missionDescription(mission),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('adventure-start-mission'),
              onPressed: mission == null || _starting ? null : _start,
              icon: _starting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_starting ? 'กำลังเปิด…' : 'เริ่มภารกิจ'),
            ),
            if (widget.onStartDialogue != null) OutlinedButton(
              key: const ValueKey('adventure-start-dialogue'),
              onPressed: mission == null || _starting ? null : () => _start(dialogue: true),
              child: const Text('Dialogue mission'),
            ),
          ],
        ),
      ),
    );
  }
}

String _missionDescription(AdventureMissionRef mission) =>
    switch (mission.kind) {
      AdventureMissionKind.resume => 'เรียนต่อจากเซสชันเดิม',
      AdventureMissionKind.review =>
        'ทบทวน ${mission.content.length} รายการที่ถึงเวลา',
      AdventureMissionKind.recommendation => 'เริ่มกิจกรรมที่แนะนำสำหรับวันนี้',
    };
