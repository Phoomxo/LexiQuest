import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MasteryDashboardScreen extends StatelessWidget {
  final double listeningScore;
  final double pronunciationScore;
  final double spellingScore;
  final double retentionScore;
  final int streakDays;

  const MasteryDashboardScreen({
    super.key,
    this.listeningScore = 85.0,
    this.pronunciationScore = 78.0,
    this.spellingScore = 92.0,
    this.retentionScore = 80.0,
    this.streakDays = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mastery & Analytics Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Streak Card
            Card(
              elevation: 4,
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.deepOrange,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$streakDays Days Streak!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                        const Text('ฝึกฝนต่อเนื่องรายวันยอดเยี่ยมมาก!'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'แผนภูมิความเชี่ยวชาญทักษะ 4 ด้าน (Skill Radar)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  radarBorderData: const BorderSide(
                    color: Colors.indigo,
                    width: 2,
                  ),
                  gridBorderData: BorderSide(
                    color: Colors.indigo.shade100,
                    width: 1,
                  ),
                  titlePositionPercentageOffset: 0.2,
                  getTitle: (index, angle) {
                    switch (index) {
                      case 0:
                        return RadarChartTitle(
                          text: 'Listening\n($listeningScore%)',
                        );
                      case 1:
                        return RadarChartTitle(
                          text: 'Pronunciation\n($pronunciationScore%)',
                        );
                      case 2:
                        return RadarChartTitle(
                          text: 'Spelling\n($spellingScore%)',
                        );
                      case 3:
                        return RadarChartTitle(
                          text: 'Retention\n($retentionScore%)',
                        );
                      default:
                        return const RadarChartTitle(text: '');
                    }
                  },
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.indigo.withValues(alpha: 0.3),
                      borderColor: Colors.indigo,
                      entryRadius: 4,
                      dataEntries: [
                        RadarEntry(value: listeningScore),
                        RadarEntry(value: pronunciationScore),
                        RadarEntry(value: spellingScore),
                        RadarEntry(value: retentionScore),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Details List
            _buildSkillTile('Listening (การฟัง)', listeningScore, Colors.blue),
            _buildSkillTile(
              'Pronunciation (การออกเสียง)',
              pronunciationScore,
              Colors.green,
            ),
            _buildSkillTile(
              'Spelling (การสะกดคำ)',
              spellingScore,
              Colors.orange,
            ),
            _buildSkillTile(
              'Retention (ความจำ SRS)',
              retentionScore,
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillTile(String title, double score, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '${score.toStringAsFixed(1)}%',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: score / 100.0,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ],
      ),
    );
  }
}
