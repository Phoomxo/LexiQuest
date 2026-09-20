import 'package:flutter/material.dart';

/// Executes only a validated, unscored draft. No progress/database dependency.
class ManagedPracticeCard extends StatefulWidget {
  const ManagedPracticeCard({
    super.key,
    required this.word,
    required this.receipt,
  });
  final Map<String, dynamic> word, receipt;
  @override
  State<ManagedPracticeCard> createState() => _ManagedPracticeCardState();
}

class _ManagedPracticeCardState extends State<ManagedPracticeCard> {
  final _answer = TextEditingController();
  bool _open = false;
  String? _feedback;
  Map<String, dynamic>? get _draft {
    final r = widget.receipt, w = widget.word, d = r['data'];
    if (r['name'] != 'create_practice_draft' ||
        r['status'] != 'completed' ||
        d is! Map<String, dynamic> ||
        d['wordId'] != w['id'] ||
        d['revision'] != w['revision'] ||
        d['expectedAnswer'] != w['spelling'] ||
        d['awardsCredit'] != false ||
        d['draftId'] is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(d['draftId'] as String) ||
        d['prompt'] != 'พิมพ์คำภาษาอังกฤษที่หมายถึง: ${w['meaning']}') {
      return null;
    }
    return d;
  }

  @override
  void didUpdateWidget(ManagedPracticeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word || oldWidget.receipt != widget.receipt) {
      _open = false;
      _feedback = null;
      _answer.clear();
    }
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return const Text('แบบฝึกไม่พร้อมหรือข้อมูลคำเปลี่ยนแล้ว');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('เครื่องมือสร้างแบบฝึกสำเร็จ · ไม่เพิ่มคะแนน'),
            if (!_open)
              FilledButton(
                onPressed: () => setState(() => _open = true),
                child: const Text('เปิดแบบฝึก'),
              ),
            if (_open) ...[
              Text(draft['prompt'] as String),
              TextField(
                controller: _answer,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'คำตอบภาษาอังกฤษ'),
              ),
              FilledButton(
                onPressed: () => setState(() {
                  final answer = _answer.text.trim();
                  _feedback = answer.isEmpty
                      ? 'กรอกคำตอบก่อน'
                      : answer.toLowerCase() ==
                            (draft['expectedAnswer'] as String).toLowerCase()
                      ? 'ถูกต้อง · แบบฝึกนี้ไม่เพิ่มคะแนน'
                      : 'ยังไม่ถูก ลองอีกครั้ง';
                }),
                child: const Text('ตรวจคำตอบ'),
              ),
              if (_feedback != null)
                Semantics(liveRegion: true, child: Text(_feedback!)),
            ],
          ],
        ),
      ),
    );
  }
}
