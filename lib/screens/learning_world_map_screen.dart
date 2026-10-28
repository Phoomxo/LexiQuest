import 'package:flutter/material.dart';
import 'cefr_selection_screen.dart';

class CampaignNode {
  final String level;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isUnlocked;

  const CampaignNode({
    required this.level,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isUnlocked,
  });
}

class LearningWorldMapScreen extends StatelessWidget {
  const LearningWorldMapScreen({super.key});

  final List<CampaignNode> _nodes = const [
    CampaignNode(
      level: 'A1',
      title: 'เกาะเริ่มต้น (A1 Starter Island)',
      description: 'คำศัพท์พื้นฐานชีวิตประจำวัน',
      icon: Icons.landscape,
      color: Colors.green,
      isUnlocked: true,
    ),
    CampaignNode(
      level: 'A2',
      title: 'ป่าพฤกษา (A2 Forest of Phrases)',
      description: 'ประโยคและการเดินทางทั่วไป',
      icon: Icons.forest,
      color: Colors.teal,
      isUnlocked: true,
    ),
    CampaignNode(
      level: 'B1',
      title: 'เมืองการค้า (B1 Business City)',
      description: 'การสื่อสารในงานและสังคม',
      icon: Icons.location_city,
      color: Colors.blue,
      isUnlocked: true,
    ),
    CampaignNode(
      level: 'B2',
      title: 'วิทยาลัยความรู้ (B2 Academic Hub)',
      description: 'คำศัพท์ระดับสูงและบทวิเคราะห์',
      icon: Icons.school,
      color: Colors.indigo,
      isUnlocked: false,
    ),
    CampaignNode(
      level: 'C1',
      title: 'ปราสาทสัทศาสตร์ (C1 Phonetic Castle)',
      description: 'คำศัพท์เฉพาะทางและสำนวนลึกซึ้ง',
      icon: Icons.castle,
      color: Colors.purple,
      isUnlocked: false,
    ),
    CampaignNode(
      level: 'C2',
      title: 'หอคอยเพชร (C2 Diamond Spire)',
      description: 'ระดับความเชี่ยวชาญสูงสุด',
      icon: Icons.auto_awesome,
      color: Colors.amber,
      isUnlocked: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แผนที่ท่องโลกคำศัพท์ (World Map Campaign)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal.shade900,
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20.0),
        itemCount: _nodes.length,
        itemBuilder: (context, index) {
          final node = _nodes[index];
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 10.0),
            child: Column(
              children: [
                InkWell(
                  onTap: node.isUnlocked
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CefrSelectionScreen(),
                            ),
                          );
                        }
                      : null,
                  child: Card(
                    elevation: node.isUnlocked ? 4 : 1,
                    color: node.isUnlocked
                        ? node.color.withValues(alpha: 0.15)
                        : Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: node.isUnlocked
                            ? node.color
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: node.isUnlocked
                                ? node.color
                                : Colors.grey,
                            child: Icon(
                              node.isUnlocked ? node.icon : Icons.lock,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${node.level}] ${node.title}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: node.isUnlocked
                                        ? Colors.black87
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  node.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: node.isUnlocked
                                        ? Colors.black54
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (index < _nodes.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.arrow_downward, color: Colors.grey),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
