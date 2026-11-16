import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../services/cefr_service.dart';
import 'srs_flashcards_screen.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

class CefrSelectionScreen extends StatefulWidget {
  final CefrService? cefrService;
  final String? initialLevel;

  const CefrSelectionScreen({super.key, this.cefrService, this.initialLevel});

  @override
  State<CefrSelectionScreen> createState() => _CefrSelectionScreenState();
}

class _CefrSelectionScreenState extends State<CefrSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final CefrService _cefrService;
  late final TabController _tabController;
  String _selectedCategory = 'ALL';
  String _searchQuery = '';

  static const List<String> _levels = [
    'ALL',
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];
  static const List<String> _categories = [
    'ALL',
    'Daily Life',
    'Work/Business',
    'Academic',
    'Technology',
    'Science',
    'Travel',
    'Philosophy',
    'Animals',
    'Food',
  ];

  static const Map<String, String> _categoryLabels = {
    'Daily Life': 'ชีวิตประจำวัน',
    'Work/Business': 'งานและธุรกิจ',
    'Academic': 'การเรียน',
    'Technology': 'เทคโนโลยี',
    'Science': 'วิทยาศาสตร์',
    'Travel': 'การเดินทาง',
    'Philosophy': 'แนวคิดและปรัชญา',
    'Animals': 'สัตว์',
    'Food': 'อาหาร',
  };

  @override
  void initState() {
    super.initState();
    _cefrService = widget.cefrService ?? CefrService();
    final requestedIndex = _levels.indexOf(
      widget.initialLevel?.toUpperCase() ?? 'ALL',
    );
    _tabController = TabController(
      length: _levels.length,
      initialIndex: requestedIndex < 0 ? 0 : requestedIndex,
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentLevel => _levels[_tabController.index];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filteredWords = _cefrService.filter(
      level: _currentLevel,
      category: _selectedCategory,
      searchQuery: _searchQuery,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'คำศัพท์ตามระดับ'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _levels
              .map((lvl) => Tab(text: lvl == 'ALL' ? 'ทั้งหมด' : 'ระดับ $lvl'))
              .toList(),
        ),
      ),
      body: AdaptiveContentPane(
        child: ListView.builder(
          itemCount: filteredWords.isEmpty ? 3 : filteredWords.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'ค้นหาคำศัพท์ หรือ คำแปล...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: ChoiceChip(
                              label: Text(
                                cat == 'ALL'
                                    ? 'ทุกหมวด'
                                    : _categoryLabels[cat] ?? cat,
                              ),
                              selected: isSelected,
                              selectedColor: colors.secondaryContainer,
                              onSelected: (val) {
                                if (val) {
                                  setState(() {
                                    _selectedCategory = cat;
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            }
            if (index == 1) {
              return Container(
                key: const ValueKey('cefr-summary'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: colors.surfaceContainerLow,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'พบ ${filteredWords.length} คำศัพท์',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: filteredWords.isNotEmpty
                          ? () {
                              final wordMaps = filteredWords
                                  .map(
                                    (w) => {
                                      'word': w.word,
                                      'translation': w.meaning,
                                      'example': w.exampleSentence,
                                    },
                                  )
                                  .toList();
                              AppNavigator.pushPage<void>(
                                context,
                                AppPage<void>(
                                  name: 'learning/cefr-srs',
                                  builder: (context) =>
                                      SrsFlashcardsScreen(wordList: wordMaps),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.style, size: 18),
                      label: const Text('เริ่มทบทวนรายการนี้'),
                    ),
                  ],
                ),
              );
            }
            if (filteredWords.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('ไม่พบคำศัพท์ตรงตามเงื่อนไขที่กรอง')),
              );
            }

            final item = filteredWords[index - 2];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      key: ValueKey('cefr-level-${item.cefrLevel}'),
                      backgroundColor: colors.primaryContainer,
                      child: Text(
                        item.cefrLevel,
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                item.word,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  _categoryLabels[item.category] ??
                                      item.category,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                          Text(
                            item.meaning,
                            style: TextStyle(
                              color: colors.tertiary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'ตัวอย่าง: “${item.exampleSentence}”',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
