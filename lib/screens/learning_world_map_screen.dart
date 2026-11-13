import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';
import 'cefr_selection_screen.dart';

class CampaignNode {
  const CampaignNode({
    required this.level,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String level;
  final String title;
  final String description;
  final IconData icon;
}

class LearningWorldMapScreen extends StatelessWidget {
  const LearningWorldMapScreen({super.key});

  final List<CampaignNode> _nodes = const [
    CampaignNode(
      level: 'A1',
      title: 'เกาะเริ่มต้น · ระดับ A1',
      description: 'คำศัพท์พื้นฐานชีวิตประจำวัน',
      icon: Icons.landscape,
    ),
    CampaignNode(
      level: 'A2',
      title: 'ป่าคำและวลี · ระดับ A2',
      description: 'ประโยคและการเดินทางทั่วไป',
      icon: Icons.forest,
    ),
    CampaignNode(
      level: 'B1',
      title: 'เมืองแห่งการสื่อสาร · ระดับ B1',
      description: 'การสื่อสารในงานและสังคม',
      icon: Icons.location_city,
    ),
    CampaignNode(
      level: 'B2',
      title: 'ศูนย์ความรู้ · ระดับ B2',
      description: 'คำศัพท์ระดับสูงและบทวิเคราะห์',
      icon: Icons.school,
    ),
    CampaignNode(
      level: 'C1',
      title: 'ปราสาทการออกเสียง · ระดับ C1',
      description: 'คำศัพท์เฉพาะทางและสำนวนลึกซึ้ง',
      icon: Icons.castle,
    ),
    CampaignNode(
      level: 'C2',
      title: 'หอคอยผู้เชี่ยวชาญ · ระดับ C2',
      description: 'ระดับความเชี่ยวชาญสูงสุด',
      icon: Icons.auto_awesome,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'แผนที่การเรียนรู้'),
        centerTitle: true,
      ),
      body: AdaptiveContentPane(
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _nodes.length,
          itemBuilder: (context, index) {
            final node = _nodes[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Card(
                    color: colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => AppNavigator.pushPage<void>(
                        context,
                        AppPage<void>(
                          name: 'learning/cefr',
                          builder: (_) =>
                              CefrSelectionScreen(initialLevel: node.level),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: colors.primaryContainer,
                              child: Icon(
                                node.icon,
                                color: colors.onPrimaryContainer,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    node.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    node.description,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index < _nodes.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Icon(Icons.arrow_downward),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
