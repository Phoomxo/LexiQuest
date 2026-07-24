import 'package:flutter/material.dart';
import '../models/srs_item.dart';
import '../services/weakness_clinic_service.dart';
import 'srs_flashcards_screen.dart';

class WeaknessClinicScreen extends StatefulWidget {
  final WeaknessClinicService? clinicService;
  final List<SrsItem>? customItems;

  const WeaknessClinicScreen({super.key, this.clinicService, this.customItems});

  @override
  State<WeaknessClinicScreen> createState() => _WeaknessClinicScreenState();
}

class _WeaknessClinicScreenState extends State<WeaknessClinicScreen> {
  late final WeaknessClinicService _clinicService;
  late List<SrsItem> _weaknessItems;

  @override
  void initState() {
    super.initState();
    _clinicService = widget.clinicService ?? const WeaknessClinicService();
    final items =
        widget.customItems ??
        [
          SrsItem(
            word: 'ephemeral',
            boxLevel: 1,
            intervalDays: 1,
            lastReviewedAt: DateTime.now(),
            nextReviewAt: DateTime.now(),
          ),
          SrsItem(
            word: 'meticulous',
            boxLevel: 1,
            intervalDays: 1,
            lastReviewedAt: DateTime.now(),
            nextReviewAt: DateTime.now(),
          ),
          SrsItem(
            word: 'challenge',
            boxLevel: 2,
            intervalDays: 2,
            lastReviewedAt: DateTime.now(),
            nextReviewAt: DateTime.now(),
          ),
        ];
    _weaknessItems = _clinicService.curateWeaknessDeck(items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'คลินิกซ่อมแซมจุดอ่อน (Weakness Clinic)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepOrange,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.healing, color: Colors.deepOrange, size: 40),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ระบบคัดสรรคำศัพท์ที่คุณลังเลหรือทำผิดบ่อยมารวบรวมให้ฝึกซ้อมเป็นพิเศษ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _weaknessItems.isEmpty
                  ? const Center(
                      child: Text('ไม่มีคำศัพท์จุดอ่อนในขณะนี้ ยอดเยี่ยมมาก!'),
                    )
                  : ListView.builder(
                      itemCount: _weaknessItems.length,
                      itemBuilder: (context, index) {
                        final item = _weaknessItems[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.redAccent,
                              child: Text(
                                'B${item.boxLevel}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              item.word,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Text(
                              'ความง่าย: ${(item.easeFactor * 100).toStringAsFixed(0)}%',
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _weaknessItems.isNotEmpty
                  ? () {
                      final wordMaps = _weaknessItems
                          .map(
                            (item) => {
                              'word': item.word,
                              'translation': 'คำศัพท์ในคลินิกจุดอ่อน',
                              'example': 'Practice in weakness clinic deck.',
                            },
                          )
                          .toList();

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SrsFlashcardsScreen(wordList: wordMaps),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.fitness_center),
              label: const Text('เริ่มฝึกซ่อมจุดอ่อนทันที'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
