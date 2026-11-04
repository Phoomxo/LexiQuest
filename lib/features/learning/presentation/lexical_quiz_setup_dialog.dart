import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../learning_packs/domain/learning_pack.dart';
import '../domain/accepted_quiz_plan.dart';
import '../domain/learning_models.dart';

class LexicalQuizSetupDialog extends StatefulWidget {
  LexicalQuizSetupDialog({
    super.key,
    required this.packVersionId,
    required Iterable<LearningPackEntry> entries,
    this.packTitle,
    this.cefrLevel,
  }) : entries = List.unmodifiable(entries);

  final String packVersionId;
  final List<LearningPackEntry> entries;
  final String? packTitle;
  final String? cefrLevel;

  @override
  State<LexicalQuizSetupDialog> createState() => _LexicalQuizSetupDialogState();
}

class _LexicalQuizSetupDialogState extends State<LexicalQuizSetupDialog> {
  final _form = GlobalKey<FormState>();
  final _minutes = TextEditingController();
  late LexicalQuizInput _input;
  late int _count;
  bool _audio = false;
  bool _largeControls = false;
  bool _reduceMotion = false;
  bool _hints = true;

  List<String> _codes(LexicalQuizInput input) => [
    for (final entry in widget.entries)
      if (entry.definition?.trim().isNotEmpty == true &&
          (input == LexicalQuizInput.definitionTyped ||
              entry.definitionQuestion != null))
        entry.code,
  ].take(100).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _input = _codes(LexicalQuizInput.definitionChoice).isEmpty
        ? LexicalQuizInput.definitionTyped
        : LexicalQuizInput.definitionChoice;
    _count = _codes(_input).length.clamp(0, 10);
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _start() {
    if (_count < 1 || !_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      LexicalQuizConfiguration(
        packVersionId: widget.packVersionId,
        entryCodes: _codes(_input),
        input: _input,
        limit: _count,
        hints: _hints ? QuizHintPolicy.optional : QuizHintPolicy.disabled,
        settings: LexicalQuizSettings(
          advisoryMinutes: _minutes.text.isEmpty
              ? null
              : int.parse(_minutes.text),
          manualAudio: _audio,
          accessibleInput: _largeControls,
          reduceMotion:
              _reduceMotion || MediaQuery.disableAnimationsOf(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codes = _codes(_input);
    final systemReducedMotion = MediaQuery.disableAnimationsOf(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('ตั้งค่าฝึกจากนิยาม'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.packTitle != null) Text(widget.packTitle!),
            if (widget.cefrLevel != null)
              Text('ระดับแพ็ก CEFR ${widget.cefrLevel}'),
            DropdownButtonFormField<LexicalQuizInput>(
              key: const ValueKey('definition-input-mode'),
              initialValue: _input,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'รูปแบบคำตอบ'),
              items: [
                for (final input in LexicalQuizInput.values)
                  DropdownMenuItem(
                    value: input,
                    enabled: _codes(input).isNotEmpty,
                    child: Text(
                      input == LexicalQuizInput.definitionChoice
                          ? 'เลือกคำศัพท์'
                          : 'พิมพ์คำศัพท์',
                    ),
                  ),
              ],
              onChanged: (input) {
                if (input == null) return;
                setState(() {
                  _input = input;
                  _count = _count.clamp(1, _codes(input).length);
                });
              },
            ),
            const SizedBox(height: 16),
            if (codes.isEmpty)
              const Text('ชุดนี้ยังไม่มีนิยามสำหรับฝึก เลือกชุดคำศัพท์อื่นได้')
            else
              DropdownButtonFormField<int>(
                key: ValueKey(('definition-item-count', _input)),
                initialValue: _count,
                decoration: const InputDecoration(labelText: 'จำนวนคำ'),
                items: [
                  for (var count = 1; count <= codes.length; count++)
                    DropdownMenuItem(value: count, child: Text('$count คำ')),
                ],
                onChanged: (count) {
                  if (count != null) setState(() => _count = count);
                },
              ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('definition-time-goal'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(
                labelText: 'เป้าหมายเวลา (นาที)',
                helperText: 'เว้นว่างได้ · พักหรือจบเมื่อพร้อม',
              ),
              validator: (text) {
                if (text == null || text.isEmpty) return null;
                final minutes = int.tryParse(text);
                return minutes == null || minutes < 1 || minutes > 180
                    ? 'ระบุ 1–180 นาที หรือเว้นว่าง'
                    : null;
              },
            ),
            SwitchListTile(
              key: const ValueKey('definition-hints'),
              contentPadding: EdgeInsets.zero,
              value: _hints,
              onChanged: (value) => setState(() => _hints = value),
              title: const Text('อนุญาตคำใบ้'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _audio,
              onChanged: (value) => setState(() => _audio = value),
              title: const Text('ปุ่มฟังคำหลังตอบ'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _largeControls,
              onChanged: (value) => setState(() => _largeControls = value),
              title: const Text('ปุ่มขนาดใหญ่'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reduceMotion || systemReducedMotion,
              onChanged: systemReducedMotion
                  ? null
                  : (value) => setState(() => _reduceMotion = value),
              title: const Text('ลดการเคลื่อนไหว'),
              subtitle: systemReducedMotion
                  ? const Text('เปิดตามการตั้งค่าระบบ')
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: const ValueKey('definition-start'),
          onPressed: codes.isEmpty ? null : _start,
          child: const Text('เริ่มฝึก'),
        ),
      ],
    );
  }
}
