import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ai_tutor_screen.dart';
import 'avatar_equipment_screen.dart';
import 'boss_battle_screen.dart';
import 'cefr_article_reader_screen.dart';
import 'cefr_diagnostic_test_screen.dart';
import 'cefr_selection_screen.dart';
import 'dictation_quiz_screen.dart';
import 'learning_world_map_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'object_scanner_screen.dart';
import 'phonetic_explorer_screen.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';
import 'sentence_scramble_screen.dart';
import 'shadowing_challenge_screen.dart';
import 'smart_audio_playlist_screen.dart';
import 'srs_flashcards_screen.dart';
import 'ghost_shadow_duel_screen.dart';
import 'interactive_storybook_screen.dart';
import 'wordbook_import_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เลือกรูปแบบการเรียนรู้ LexiQuest',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple, Colors.indigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 🌟 1. คลังคำศัพท์มาตรฐาน CEFR (A1 - C2)
            _buildModeButton(
              context,
              title: "คลังคำศัพท์ CEFR (A1 - C2)",
              icon: Icons.auto_awesome,
              color: Colors.indigo,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CefrSelectionScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📊 2. แดชบอร์ดสรุปทักษะ & Analytics
            _buildModeButton(
              context,
              title: "แดชบอร์ดสรุปทักษะ & Radar Chart",
              icon: Icons.bar_chart,
              color: Colors.purple,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MasteryDashboardScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📝 3. แบบทดสอบประเมินระดับ CEFR แรกเข้า
            _buildModeButton(
              context,
              title: "แบบทดสอบประเมินระดับ CEFR",
              icon: Icons.assignment_turned_in,
              color: Colors.teal,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CefrDiagnosticTestScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🎧 4. โหมดฝึกฟังสะกดคำ (Slow-Mo Dictation Quiz)
            _buildModeButton(
              context,
              title: "โหมดฝึกฟังสะกดคำ (Dictation Quiz)",
              icon: Icons.hearing,
              color: Colors.deepOrange,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const DictationQuizScreen(targetWord: 'challenge'),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🗣️ 5. โหมดฝึกพูดตามจังหวะ AI (Shadowing Challenge)
            _buildModeButton(
              context,
              title: "โหมดฝึกพูดตามจังหวะ AI (Shadowing)",
              icon: Icons.record_voice_over,
              color: Colors.pink,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ShadowingChallengeScreen(
                      referenceSentence:
                          'Practice makes perfect in English learning.',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🧩 6. โหมดเรียงประโยคภาษาอังกฤษ (Sentence Scramble)
            _buildModeButton(
              context,
              title: "โหมดเรียงประโยค (Sentence Scramble)",
              icon: Icons.extension,
              color: Colors.blueAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SentenceScrambleScreen(
                      targetSentence: 'Knowledge is power for future success',
                      translation: 'ความรู้คือพลังสำหรับความสำเร็จในอนาคต',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🃏 7. โหมดทบทวนการ์ดคำศัพท์ (SRS Flashcards)
            _buildModeButton(
              context,
              title: "โหมดทบทวนการ์ดคำศัพท์ (SRS Flashcards)",
              icon: Icons.style,
              color: Colors.green,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SrsFlashcardsScreen(
                      wordList: [
                        {
                          'word': 'opportunity',
                          'translation': 'โอกาส',
                          'example': 'This is a great opportunity.',
                        },
                        {
                          'word': 'sustainable',
                          'translation': 'ยั่งยืน',
                          'example': 'Sustainable energy sources.',
                        },
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🎧 8. เครื่องเล่นเสียงทบทวนคำศัพท์ต่อเนื่อง (Smart Audio Playlist)
            _buildModeButton(
              context,
              title: "เครื่องเล่นเสียงทบทวนศัพท์ (Audio Playlist)",
              icon: Icons.headphones,
              color: Colors.deepPurpleAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SmartAudioPlaylistScreen(
                      wordList: [
                        {
                          'word': 'opportunity',
                          'translation': 'โอกาส',
                          'example': 'This is a great opportunity.',
                        },
                        {
                          'word': 'sustainable',
                          'translation': 'ยั่งยืน',
                          'example': 'Sustainable energy sources.',
                        },
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📰 9. อ่านบทความตามระดับ CEFR (CEFR Article Reader)
            _buildModeButton(
              context,
              title: "อ่านบทความ CEFR (Article Reader)",
              icon: Icons.menu_book,
              color: Colors.brown,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CefrArticleReaderScreen(
                      title: 'The Future of Technology',
                      content:
                          'Sustainable technology brings incredible opportunities for innovative learning and development',
                      cefrLevel: 'B2',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // ⚔️ 10. โหมดต่อสู้บอสคำศัพท์ประจำวัน (Daily Boss Battle)
            _buildModeButton(
              context,
              title: "ต่อสู้บอสคำศัพท์ (Daily Boss Battle)",
              icon: Icons.flash_on,
              color: Colors.red.shade800,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BossBattleScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🤺 10.1 โหมดดวลร่างเงาตนเอง (Your Next Opponent Is You)
            _buildModeButton(
              context,
              title: "🤺 ดวลร่างเงาตนเอง (Ghost Shadow Duel)",
              icon: Icons.psychology,
              color: Colors.purple.shade900,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GhostShadowDuelScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📖 10.2 โหมดนิทานสองภาษา CEFR (Interactive Storybook)
            _buildModeButton(
              context,
              title: "📖 นิทานสองภาษา (Interactive Storybook)",
              icon: Icons.auto_stories,
              color: Colors.teal.shade800,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InteractiveStorybookScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📥 11. นำเข้าสมุดคำศัพท์ส่วนตัว (Custom Wordbook Import)
            _buildModeButton(
              context,
              title: "นำเข้าคลังคำศัพท์ส่วนตัว (Import Wordbook)",
              icon: Icons.file_upload,
              color: Colors.teal,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WordbookImportScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🔤 12. สำรวจสัทอักษร IPA (Phonetic Explorer)
            _buildModeButton(
              context,
              title: "สำรวจสัทอักษร IPA (Phonetic Explorer)",
              icon: Icons.record_voice_over,
              color: Colors.teal.shade800,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PhoneticExplorerScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🛡️ 13.1 อุปกรณ์สวมใส่ตัวละคร & บัฟพลัง RPG (Avatar Equipment)
            _buildModeButton(
              context,
              title: "🛡️ อุปกรณ์ตัวละคร & บัฟพลัง RPG (Avatar Gear)",
              icon: Icons.shield,
              color: Colors.deepPurple.shade700,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AvatarEquipmentScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🤖 14. จำลองบทสนทนากับ AI Tutor (AI Roleplay Tutor)
            _buildModeButton(
              context,
              title: "จำลองบทสนทนา AI (AI Roleplay Tutor)",
              icon: Icons.forum,
              color: Colors.indigo.shade800,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AiTutorScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📸 15. สแกนวัตถุคำศัพท์ (Object Scanner)
            _buildModeButton(
              context,
              title: "สแกนวัตถุคำศัพท์ (Camera Object Scanner)",
              icon: Icons.camera_alt,
              color: Colors.blueGrey.shade800,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ObjectScannerScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🗺️ 16. แผนที่ท่องโลกคำศัพท์ (World Map Campaign)
            _buildModeButton(
              context,
              title: "แผนที่ท่องโลกคำศัพท์ (World Map Campaign)",
              icon: Icons.map,
              color: Colors.teal.shade900,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LearningWorldMapScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 🎯 8. เริ่มด้วยคำศัพท์ในแอพ (Default Quiz)
            _buildModeButton(
              context,
              title: "เริ่มด้วยคำศัพท์ในแอพ",
              icon: Icons.play_arrow,
              color: Colors.red,
              onPressed: () async {
                final CollectionReference vocabCollection = FirebaseFirestore
                    .instance
                    .collection('vocabulary');
                final querySnapshot = await vocabCollection.get();

                if (querySnapshot.docs.isEmpty) {
                  if (!context.mounted) return;
                  _showSnackBar(context, 'ไม่มีคำศัพท์ในคลัง!');
                  return;
                }

                final vocabList = querySnapshot.docs.map((doc) {
                  return {
                    'word': doc['word'],
                    'meaning': doc['meaning'],
                    'part_of_speech': doc['part_of_speech'],
                  };
                }).toList()..shuffle();

                final selectedWords = vocabList.take(10).toList();

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QuizScreen(vocabList: selectedWords),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 📝 9. เริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา (Categories Quiz)
            _buildModeButton(
              context,
              title: "เริ่มด้วยคำศัพท์หมวดผู้ใช้",
              icon: Icons.list_alt,
              color: Colors.orange,
              onPressed: () async {
                final selectedCategory = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SelectCategoryForQuiz(),
                  ),
                );

                if (selectedCategory != null) {
                  final CollectionReference wordsCollection = FirebaseFirestore
                      .instance
                      .collection('categories')
                      .doc(selectedCategory)
                      .collection('words');

                  final querySnapshot = await wordsCollection.get();

                  if (querySnapshot.docs.isEmpty) {
                    if (!context.mounted) return;
                    _showSnackBar(context, 'ไม่มีคำศัพท์ในหมวดหมู่นี้!');
                    return;
                  }

                  final vocabList = querySnapshot.docs.map((doc) {
                    return {
                      'word': doc['word'],
                      'meaning': doc['meaning'],
                      'part_of_speech': doc['part_of_speech'],
                    };
                  }).toList()..shuffle();

                  final selectedWords = vocabList.take(10).toList();

                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          QuizScreen(vocabList: selectedWords),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
