import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../models/cefr_word.dart';
import '../services/cefr_service.dart';
import 'cefr_sample_card_screen.dart';
import 'srs_flashcards_screen.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

class CefrSelectionScreen extends StatefulWidget {
  final CefrService? cefrService;
  final String? initialLevel;
  final bool sampleDeck;
  final String returnLabel;

  const CefrSelectionScreen({
    super.key,
    this.cefrService,
    this.initialLevel,
    this.sampleDeck = false,
    this.returnLabel = 'เลือกระดับอื่น',
  });

  static const samples = <String, ({String word, String topic})>{
    'A1': (word: 'hello', topic: 'คำในชีวิตประจำวัน'),
    'A2': (word: 'journey', topic: 'การเดินทาง'),
    'B1': (word: 'achieve', topic: 'การทำงาน'),
    'B2': (word: 'sustainable', topic: 'วิทยาศาสตร์'),
    'C1': (word: 'meticulous', topic: 'การทำงาน'),
    'C2': (word: 'ephemeral', topic: 'ปรัชญา'),
  };

  @override
  State<CefrSelectionScreen> createState() => _CefrSelectionScreenState();
}

class _CefrSelectionScreenState extends State<CefrSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final CefrService _cefrService = widget.cefrService ?? CefrService();
  late final TabController _tabController;
  final _sampleSearch = TextEditingController();
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
    _sampleSearch.dispose();
    super.dispose();
  }

  String get _currentLevel => _levels[_tabController.index];

  @override
  Widget build(BuildContext context) {
    if (widget.sampleDeck) return _buildSampleDeck(context);
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

  Widget _buildSampleDeck(BuildContext context) {
    final level = widget.initialLevel?.toUpperCase();
    final sample = CefrSelectionScreen.samples[level];
    final word = CefrService.defaultCefrDatabase
        .where((word) => word.cefrLevel == level && word.word == sample?.word)
        .firstOrNull;
    final query = _searchQuery.trim().toLowerCase();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          sample == null ? 'ชุดคำตัวอย่าง' : 'คำศัพท์ระดับ $level',
        ),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (sample != null) ...[
                Text(sample.topic, style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: _sampleSearch,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'ค้นคำในชุดนี้',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                if (_searchQuery.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () {
                        _sampleSearch.clear();
                        FocusScope.of(context).unfocus();
                        setState(() => _searchQuery = '');
                      },
                      child: const Text('ล้างคำค้น'),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (word != null &&
                  sample != null &&
                  (word.word.toLowerCase().contains(query) ||
                      word.meaning.toLowerCase().contains(query))) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('คำในชุดตัวอย่าง'),
                        Text(word.word, style: theme.textTheme.headlineSmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _openSampleCard(word, sample.topic),
                  child: const Text('เริ่มทบทวนคำนี้'),
                ),
              ] else
                Semantics(
                  liveRegion: true,
                  child: Text(
                    word == null
                        ? 'ยังไม่มีบัตรตัวอย่างสำหรับระดับนี้'
                        : 'ไม่พบคำในชุดนี้',
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(widget.returnLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSampleCard(CefrWord word, String topic) async {
    if (ModalRoute.isCurrentOf(context) != true) return;
    FocusScope.of(context).unfocus();
    final leaveDeck = await AppNavigator.pushPage<bool>(
      context,
      AppPage<bool>(
        name: 'learning/cefr-sample-card',
        builder: (_) => CefrSampleCardScreen(
          word: word,
          topic: topic,
          returnLabel: widget.returnLabel,
        ),
      ),
    );
    if (leaveDeck == true &&
        mounted &&
        ModalRoute.isCurrentOf(context) == true) {
      Navigator.maybePop(context);
    }
  }
}
