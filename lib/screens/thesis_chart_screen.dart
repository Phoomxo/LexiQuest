import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ThesisChartScreen extends StatelessWidget {
  final double preTestScore;
  final double postTestScore;
  final List<double> latencyTrend;

  const ThesisChartScreen({
    super.key,
    required this.preTestScore,
    required this.postTestScore,
    required this.latencyTrend,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'กราฟผลสัมฤทธิ์งานวิจัย (Thesis Auto-Chart)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. กราฟเปรียบเทียบคะแนน Pre-Test vs Post-Test',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: preTestScore,
                          color: Colors.orange,
                          width: 28,
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: postTestScore,
                          color: Colors.green,
                          width: 28,
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          if (val == 0) {
                            return Text(
                              'Pre-Test (${preTestScore.toStringAsFixed(1)}%)',
                            );
                          }
                          if (val == 1) {
                            return Text(
                              'Post-Test (${postTestScore.toStringAsFixed(1)}%)',
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 40),
            const Text(
              '2. กราฟแนวโน้มความเร็วการตอบสะสม (Latency Trend ms)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 500,
                  maxY: 3000,
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        latencyTrend.length,
                        (index) =>
                            FlSpot(index.toDouble(), latencyTrend[index]),
                      ),
                      isCurved: true,
                      color: Colors.blueAccent,
                      barWidth: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
