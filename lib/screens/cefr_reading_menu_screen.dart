import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'cefr_article_reader_screen.dart';
import 'cefr_diagnostic_test_screen.dart';
import 'cefr_selection_screen.dart';
import 'learning_world_map_screen.dart';

class CefrReadingMenuScreen extends StatelessWidget {
  const CefrReadingMenuScreen({
    super.key,
    required this.fieldFeatures,
    required this.onReturnHome,
  });

  final FieldFeatureRegistry fieldFeatures;
  final VoidCallback onReturnHome;

  static const _articles = {
    'A1': (
      title: 'ซื้อตั๋วรถไฟ',
      detail: 'ประโยคสั้นที่ช่องขายตั๋ว',
      text: 'One ticket, please.\nI pay and take my ticket.',
    ),
    'A2': (
      title: 'นัดกันที่สถานี',
      detail: 'อ่านเรื่องแล้วฝึกใช้คำ',
      text:
          'Mina arrives at the station.\n'
          'Her friend is on platform two.\n\n'
          'She follows the signs.\n'
          'They meet on the platform.',
    ),
  };

  void _open(BuildContext context, String name, WidgetBuilder builder) {
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: 'learning/cefr/$name', builder: builder),
    );
  }

  Widget _article(String level, {String returnLabel = 'กลับไปเลือกบทเรียน'}) {
    final text = _articles[level]!;
    return CefrArticleReaderScreen(
      title: text.title,
      content: text.text,
      cefrLevel: level,
      returnLabel: returnLabel,
      onReturnHome: onReturnHome,
      showStationExercise: level == 'A2',
      onOpenNext: level == 'A1'
          ? (from) => _open(
              from,
              'read-a2',
              (_) => _article('A2', returnLabel: 'กลับไปเรื่องซื้อตั๋วรถไฟ'),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final canRead =
        fieldFeatures.isVisible(FieldFeature.reading) &&
        (features?.isVisible(Feature.reading) ?? true);
    final canBrowse =
        fieldFeatures.isVisible(FieldFeature.vocabulary) &&
        (features?.isVisible(Feature.vocabulary) ?? true);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'คำศัพท์และบทอ่าน'),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (canRead) ...[
                if (canBrowse)
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('เลือกคำตามระดับ'),
                    subtitle: const Text('A1 ถึง C2 · บัตรคำตัวอย่าง'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      context,
                      'world-map',
                      (_) => const LearningWorldMapScreen(sampleDeck: true),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.quiz_outlined),
                  title: const Text('ลองตอบก่อนเลือกระดับ'),
                  subtitle: const Text('5 ข้อ · ดูผลแล้วเลือกเรื่องอ่าน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    'try-questions',
                    (_) => CefrDiagnosticTestScreen(
                      suggestedDeckBuilder: canBrowse
                          ? (_, level) => CefrSelectionScreen(
                              initialLevel: level,
                              sampleDeck: true,
                              returnLabel: 'กลับไปดูผลเดิม',
                            )
                          : null,
                      suggestedArticleTitle: (level) => _articles[level]!.title,
                      suggestedArticleBuilder: (_, level) =>
                          _article(level, returnLabel: 'กลับไปที่บทอ่านแนะนำ'),
                    ),
                  ),
                ),
                for (final level in _articles.keys)
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(_articles[level]!.title),
                    subtitle: Text(
                      'บทอ่าน $level · ${_articles[level]!.detail}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      context,
                      'read-${level.toLowerCase()}',
                      (_) => _article(level),
                    ),
                  ),
              ] else
                const Text('กิจกรรมอ่านยังไม่เปิดใช้งาน'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('กลับไปเลือกวิธีฝึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
