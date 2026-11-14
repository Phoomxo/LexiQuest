import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../models/cefr_word.dart';
import '../widgets/adaptive_content_pane.dart';

enum _SampleCardFace { recall, revealed, remembered }

class CefrSampleCardScreen extends StatefulWidget {
  const CefrSampleCardScreen({
    super.key,
    required this.word,
    required this.topic,
    required this.returnLabel,
  });

  final CefrWord word;
  final String topic;
  final String returnLabel;

  @override
  State<CefrSampleCardScreen> createState() => _CefrSampleCardScreenState();
}

class _CefrSampleCardScreenState extends State<CefrSampleCardScreen> {
  _SampleCardFace _face = _SampleCardFace.recall;

  void _show(_SampleCardFace face) => setState(() => _face = face);

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final theme = Theme.of(context);
    final remembered = _face == _SampleCardFace.remembered;
    final title = switch (_face) {
      _SampleCardFace.recall => 'นึกความหมาย',
      _SampleCardFace.revealed => 'เทียบกับคำที่นึกไว้',
      _SampleCardFace.remembered => 'ทบทวนจบแล้ว',
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, title),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${word.cefrLevel} · ${widget.topic}${remembered ? '' : ' · บัตร 1 จาก 1'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (remembered) ...[
                          Text('1 / 1', style: theme.textTheme.headlineMedium),
                          const Text('คำที่เลือกว่าจำได้'),
                          const SizedBox(height: 12),
                        ],
                        Text(word.word, style: theme.textTheme.headlineSmall),
                        if (_face != _SampleCardFace.recall)
                          Text(
                            word.meaning,
                            style: theme.textTheme.titleMedium,
                          ),
                        const SizedBox(height: 12),
                        Text(word.exampleSentence),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              switch (_face) {
                _SampleCardFace.recall => FilledButton(
                  onPressed: () => _show(_SampleCardFace.revealed),
                  child: const Text('พลิกดูความหมาย'),
                ),
                _SampleCardFace.revealed => FilledButton(
                  onPressed: () => _show(_SampleCardFace.remembered),
                  child: const Text('จำได้แล้ว'),
                ),
                _SampleCardFace.remembered => FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('กลับไปดูชุดเดิม'),
                ),
              },
              if (_face == _SampleCardFace.revealed)
                OutlinedButton(
                  onPressed: () => _show(_SampleCardFace.recall),
                  child: const Text('ยังนึกไม่ออก · ลองอีกครั้ง'),
                ),
              if (remembered)
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(widget.returnLabel),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('พักแล้วกลับชุดคำ'),
                ),
              const SizedBox(height: 12),
              const Text('ผลบัตรตัวอย่างอยู่ในรอบนี้'),
            ],
          ),
        ),
      ),
    );
  }
}
