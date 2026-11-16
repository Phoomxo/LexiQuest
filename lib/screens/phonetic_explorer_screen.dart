import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';
import '../widgets/adaptive_content_pane.dart';

class PhoneticExplorerScreen extends StatefulWidget {
  const PhoneticExplorerScreen({
    super.key,
    this.voice,
    this.targetWord,
    this.returnLabel = 'กลับไปดูคำเดิม',
  });

  final VoiceUseCases? voice;
  final String? targetWord;
  final String returnLabel;

  @override
  State<PhoneticExplorerScreen> createState() => _PhoneticExplorerScreenState();
}

typedef _Sound = ({String ipa, String word, String meaning, String mouthCue});

const _she = (
  ipa: '/ʃ/',
  word: 'she',
  meaning: 'เธอ',
  mouthCue: 'ห่อริมฝีปากเล็กน้อยแล้วปล่อยลม',
);

const _sounds = <_Sound>[
  (
    ipa: '/æ/',
    word: 'cat',
    meaning: 'แมว',
    mouthCue: 'อ้าปากแล้วออกเสียงสระสั้น',
  ),
  (
    ipa: '/θ/',
    word: 'think',
    meaning: 'คิด',
    mouthCue: 'วางปลายลิ้นระหว่างฟันแล้วพ่นลมเบา ๆ',
  ),
  _she,
  (
    ipa: '/ʒ/',
    word: 'vision',
    meaning: 'การมองเห็น',
    mouthCue: 'เสียงกลางคำคล้าย /ʃ/ แต่เส้นเสียงสั่น',
  ),
  (
    ipa: '/ŋ/',
    word: 'sing',
    meaning: 'ร้องเพลง',
    mouthCue: 'ยกโคนลิ้นแล้วปล่อยเสียงออกทางจมูก',
  ),
  (
    ipa: '/iː/',
    word: 'see',
    meaning: 'เห็น',
    mouthCue: 'เหยียดริมฝีปากแล้วลากเสียงสระยาว',
  ),
];

class _PhoneticExplorerScreenState extends State<PhoneticExplorerScreen> {
  final _scrollController = ScrollController();
  VoiceUseCases? _voice;
  _Sound? _chosenSound;
  bool _requestPending = false;
  bool _voiceFailed = false;

  bool get _isStation => widget.targetWord?.trim().toLowerCase() == 'station';

  void _chooseSound(_Sound sound) {
    if (_requestPending) return;
    setState(() {
      _chosenSound = sound;
      _voiceFailed = false;
    });
    _scrollController.jumpTo(0);
  }

  Future<void> _play(_Sound sound) async {
    if (_requestPending || ModalRoute.isCurrentOf(context) == false) return;
    final voice = _voice ??= widget.voice ?? VoiceUseCases.createOnDevice();
    setState(() {
      _requestPending = true;
      _voiceFailed = false;
    });
    var failed = false;
    try {
      await voice.speak(
        VoiceRequest.create(
          text: sound.word,
          language: 'en',
          voiceId: 'native-default',
          speed: 0.8,
          mode: VoiceMode.practice,
          contentId: sound.word,
          contentType: 'phonetic_explorer',
        ),
      );
    } on Object {
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _requestPending = false;
          _voiceFailed = failed;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _voice?.stop().ignore();
    _voice?.disposeIfOwned(widget.voice == null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetWord = widget.targetWord;
    final sound = _chosenSound ?? (_isStation ? _she : null);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          targetWord == null ? 'เลือกเสียงที่อยากฝึก' : 'แยกเสียงในคำ',
        ),
      ),
      body: SafeArea(
        child: AdaptiveContentPane(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              if (targetWord != null) ...[
                Text(targetWord, style: theme.textTheme.headlineSmall),
                if (_isStation) const Text('/ˈsteɪʃən/'),
                const SizedBox(height: 12),
              ],
              if (sound != null) ...[
                Text(sound.word, style: theme.textTheme.titleLarge),
                Text(sound.meaning),
                const SizedBox(height: 8),
                Text(sound.mouthCue),
                if (_isStation && sound == _she)
                  const Text('เสียง /ʃ/ อยู่หลังสระ /eɪ/'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _requestPending ? null : () => _play(sound),
                  child: Text(
                    'ลองเสียง ${sound.ipa} ในคำว่า ${sound.word}',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_voiceFailed)
                  Semantics(
                    liveRegion: true,
                    child: const Text('เปิดเสียงตัวอย่างไม่ได้'),
                  ),
                const SizedBox(height: 12),
              ],
              if (ModalRoute.canPopOf(context) ?? false)
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(
                    targetWord == null && widget.returnLabel == 'กลับไปดูคำเดิม'
                        ? 'กลับไปเลือกแบบฝึกฟัง'
                        : widget.returnLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (sound != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    'เลือกเสียงอื่น',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              for (final option in _sounds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Semantics(
                    selected: sound == option,
                    child: OutlinedButton(
                      onPressed: _requestPending
                          ? null
                          : () => _chooseSound(option),
                      child: Text('${option.ipa} ${option.word}'),
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
