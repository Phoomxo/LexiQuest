import 'package:flutter/material.dart';
import '../services/cefr_service.dart';
import 'srs_flashcards_screen.dart';

class CefrSelectionScreen extends StatefulWidget {
  final CefrService? cefrService;

  const CefrSelectionScreen({super.key, this.cefrService});

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

  @override
  void initState() {
    super.initState();
    _cefrService = widget.cefrService ?? CefrService();
    _tabController = TabController(length: _levels.length, vsync: this);
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
    final filteredWords = _cefrService.filter(
      level: _currentLevel,
      category: _selectedCategory,
      searchQuery: _searchQuery,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'คลังคำศัพท์ CEFR Multi-Matrix',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.amberAccent,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          tabs: _levels
              .map((lvl) => Tab(text: lvl == 'ALL' ? 'ทั้งหมด' : 'ระดับ $lvl'))
              .toList(),
        ),
      ),
      body: Column(
        children: [
          // Search & Filter header
          Padding(
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
                          label: Text(cat == 'ALL' ? 'ทุกหมวด' : cat),
                          selected: isSelected,
                          selectedColor: Colors.indigo.shade100,
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
          ),
          // Word count & Action bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'พบ ${filteredWords.length} คำศัพท์',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                ElevatedButton.icon(
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SrsFlashcardsScreen(wordList: wordMaps),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.style, size: 18),
                  label: const Text('เริ่มทบทวน SRS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Word List
          Expanded(
            child: filteredWords.isEmpty
                ? const Center(child: Text('ไม่พบคำศัพท์ตรงตามเงื่อนไขที่กรอง'))
                : ListView.builder(
                    itemCount: filteredWords.length,
                    itemBuilder: (context, index) {
                      final item = filteredWords[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getCefrColor(item.cefrLevel),
                            child: Text(
                              item.cefrLevel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item.word,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  item.category,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.meaning,
                                style: const TextStyle(
                                  color: Colors.deepOrange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Ex: "${item.exampleSentence}"',
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getCefrColor(String level) {
    switch (level.toUpperCase()) {
      case 'A1':
        return Colors.blue;
      case 'A2':
        return Colors.teal;
      case 'B1':
        return Colors.green;
      case 'B2':
        return Colors.orange;
      case 'C1':
        return Colors.deepOrange;
      case 'C2':
        return Colors.purple;
      default:
        return Colors.indigo;
    }
  }
}
