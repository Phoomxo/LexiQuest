import 'package:flutter/material.dart';
import '../services/cefr_interactive_storybook_service.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class InteractiveStorybookScreen extends StatefulWidget {
  final VoiceProvider? voiceProvider;

  const InteractiveStorybookScreen({super.key, this.voiceProvider});

  @override
  State<InteractiveStorybookScreen> createState() =>
      _InteractiveStorybookScreenState();
}

class _InteractiveStorybookScreenState
    extends State<InteractiveStorybookScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  final CefrInteractiveStorybookService _storybookService =
      const CefrInteractiveStorybookService();

  String _selectedLevel = 'A2';
  int _currentChapterIndex = 0;
  String? _selectedWordIpa;
  String? _selectedWord;

  @override
  void initState() {
    super.initState();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
      _ownsVoiceProvider = false;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
  }

  Future<void> _speakWord(String word) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: word,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: word,
          contentType: 'storybook_word',
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _voiceProvider.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _storybookService.getChapters(level: _selectedLevel);
    final activeChapter = chapters.isNotEmpty
        ? chapters[_currentChapterIndex.clamp(0, chapters.length - 1)]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CEFR Interactive Storybook (นิทานสองภาษา)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal.shade900,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Level Selector Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'เลือกระดับ CEFR นิทาน:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: ['A2', 'B2'].map((level) {
                    final isSelected = level == _selectedLevel;
                    return ChoiceChip(
                      label: Text('ระดับ $level'),
                      selected: isSelected,
                      selectedColor: Colors.teal.shade100,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedLevel = level;
                            _currentChapterIndex = 0;
                            _selectedWord = null;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (activeChapter != null) ...[
              // Story Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            activeChapter.title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          Chip(
                            backgroundColor: Colors.teal.shade50,
                            label: Text(
                              'CEFR ${activeChapter.cefrLevel}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      Text(
                        activeChapter.contentText,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'คลิกที่คำศัพท์เพื่อดูสัญลักษณ์ IPA และฟังเสียงอ่าน:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: activeChapter.vocabularyIpaMap.entries.map((
                          entry,
                        ) {
                          final word = entry.key;
                          final ipa = entry.value;
                          final isSelected = _selectedWord == word;
                          return ActionChip(
                            avatar: Icon(
                              Icons.volume_up,
                              size: 16,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.teal.shade800,
                            ),
                            label: Text('$word ($ipa)'),
                            backgroundColor: isSelected
                                ? Colors.teal
                                : Colors.teal.shade50,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.teal.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedWord = word;
                                _selectedWordIpa = ipa;
                              });
                              _speakWord(word);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_selectedWord != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'กำลังเล่นเสียงคำว่า "$_selectedWord" [IPA: $_selectedWordIpa]',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_circle_fill, color: Colors.teal),
                        onPressed: () => _speakWord(_selectedWord!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Decision Branch Card
              Card(
                color: Colors.blueGrey.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.alt_route, color: Colors.amber),
                          SizedBox(width: 8),
                          Text(
                            'ทางเลือกแตกแขนงเนื้อเรื่อง (Story Branching):',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'เพื่อก้าวไปยังบทถัดไป คุณจะเลือกแก้ปริศนาคำศัพท์ด้วยเส้นทางใด?',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '🌟 คุณเลือกเส้นทาง "สำรวจห้องสมุดโบราณ" (+30 XP)',
                              ),
                              backgroundColor: Colors.teal,
                            ),
                          );
                        },
                        icon: const Icon(Icons.explore),
                        label: const Text('เส้นทาง A: สำรวจห้องสมุดโบราณ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '⚡ คุณเลือกเส้นทาง "วิเคราะห์แบบจำลองข้อมูล" (+30 XP)',
                              ),
                              backgroundColor: Colors.amber,
                            ),
                          );
                        },
                        icon: const Icon(Icons.analytics),
                        label: const Text('เส้นทาง B: วิเคราะห์โมเดลคำศัพท์'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const Center(
                child: Text('ไม่พบบทเรียนนิทานสำหรับระดับนี้'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
