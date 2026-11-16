import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../widgets/adaptive_content_pane.dart';

enum _Step { recall, retry, write, result }

enum CefrStationExit { origin, home }

class CefrStationExerciseScreen extends StatefulWidget {
  const CefrStationExerciseScreen({
    super.key,
    required this.returnLabel,
    required this.canReturnHome,
  });

  final String? returnLabel;
  final bool canReturnHome;

  @override
  State<CefrStationExerciseScreen> createState() =>
      _CefrStationExerciseScreenState();
}

class _CefrStationExerciseScreenState extends State<CefrStationExerciseScreen> {
  final _sentence = TextEditingController();
  var _step = _Step.recall;
  bool _needsTargetWord = false;

  void _advance(_Step step) {
    if (step == _Step.result) {
      if (!RegExp(
        r'\bplatform\b',
        caseSensitive: false,
      ).hasMatch(_sentence.text)) {
        setState(() => _needsTargetWord = true);
        return;
      }
      FocusScope.of(context).unfocus();
    }
    setState(() {
      _step = step;
      _needsTargetWord = false;
    });
  }

  @override
  void dispose() {
    _sentence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.recall => 'นึกคำจากเรื่อง',
      _Step.retry => 'ลองนึกอีกครั้ง',
      _Step.write => 'ลองแต่งประโยค',
      _Step.result => 'ผลการฝึกครั้งนี้',
    };
    final theme = Theme.of(context);
    return PopScope<CefrStationExit>(
      canPop: _step == _Step.recall || _step == _Step.result,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _advance(_Step.recall);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(context, title),
        ),
        body: AdaptiveContentPane(
          child: SafeArea(
            child: ListView(
              key: ValueKey(_step),
              padding: const EdgeInsets.all(20),
              children: [
                const Text('นัดกันที่สถานี'),
                const SizedBox(height: 12),
                if (_step == _Step.recall) ...[
                  Text(
                    'They meet on the ____.',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const Text('ทั้งสองมาเจอกันที่ชานชาลา'),
                  const SizedBox(height: 12),
                  for (final word in ['platform', 'ticket'])
                    FilledButton.tonal(
                      onPressed: () => _advance(
                        word == 'platform' ? _Step.write : _Step.retry,
                      ),
                      child: Text(word),
                    ),
                ] else if (_step == _Step.retry) ...[
                  Semantics(
                    liveRegion: true,
                    child: const Text('ticket หมายถึงตั๋ว'),
                  ),
                  const Text('Her friend is on platform two.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _advance(_Step.recall),
                    child: const Text('กลับไปตอบ'),
                  ),
                ] else if (_step == _Step.write) ...[
                  const Text('They meet on the platform.'),
                  const Text('ลองใช้ platform ในประโยคของคุณ'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sentence,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 180,
                    decoration: InputDecoration(
                      labelText: 'ประโยคของฉัน',
                      errorText: _needsTargetWord
                          ? 'ใส่คำว่า platform ในประโยคก่อนดูสรุป'
                          : null,
                    ),
                    onChanged: (_) {
                      if (_needsTargetWord) {
                        setState(() => _needsTargetWord = false);
                      }
                    },
                  ),
                  FilledButton(
                    onPressed: () => _advance(_Step.result),
                    child: const Text('ดูสรุปการอ่าน'),
                  ),
                ] else ...[
                  Text('นึกได้ 1 คำ', style: theme.textTheme.headlineSmall),
                  const Text('platform · ชานชาลา'),
                  const SizedBox(height: 16),
                  const Text('ประโยคที่ลองแต่ง'),
                  Text(_sentence.text.trim()),
                  const Text('สรุปจากแบบฝึกตัวอย่างรอบนี้'),
                  if (widget.returnLabel case final label?)
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, CefrStationExit.origin),
                      child: Text(label),
                    ),
                  if (widget.canReturnHome)
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, CefrStationExit.home),
                      child: const Text('กลับหน้าฝึกภาษา'),
                    ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('กลับไปอ่านต่อ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
