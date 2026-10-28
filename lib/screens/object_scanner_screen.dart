import 'package:flutter/material.dart';
import '../services/object_vocabulary_database.dart';
import '../services/srs_service.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

/// Object Scanner experience backed by a built-in vocabulary simulation.
///
/// This version does not inspect camera, image, or ML input. It samples the
/// bundled vocabulary database, plays audio, and keeps a local result history.
class ObjectScannerScreen extends StatefulWidget {
  /// Optional voice provider for dependency injection in tests.
  final VoiceProvider? voiceProvider;

  const ObjectScannerScreen({super.key, this.voiceProvider});

  @override
  State<ObjectScannerScreen> createState() => _ObjectScannerScreenState();
}

class _ObjectScannerScreenState extends State<ObjectScannerScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;

  final ObjectVocabularyDatabase _vocabDb = const ObjectVocabularyDatabase();

  bool _isScanning = false;
  ScannedVocabulary? _currentResult;
  double _confidence = 0.0;
  final List<_ScanHistoryEntry> _scanHistory = [];
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
  }

  @override
  void dispose() {
    _voiceProvider.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  /// Draw a vocabulary sample without camera, image, or ML input.
  void _scanObject() {
    setState(() => _isScanning = true);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      // Get entries filtered by category, then pick a random one.
      List<ScannedVocabulary> pool;
      if (_selectedCategory == 'All') {
        pool = _vocabDb.allEntries;
      } else {
        pool = _vocabDb.getByCategory(_selectedCategory);
        if (pool.isEmpty) pool = _vocabDb.allEntries;
      }

      // Avoid repeating recent scans.
      final recentLabels = _scanHistory
          .take(5)
          .map((e) => e.vocab.mlLabel)
          .toSet();
      final filtered = pool
          .where((v) => !recentLabels.contains(v.mlLabel))
          .toList();
      final candidates = filtered.isNotEmpty ? filtered : pool;

      final shuffled = candidates.toList()..shuffle();
      final picked = shuffled.first;
      final simulatedConfidence = 0.75 + (0.24 * (shuffled.length % 10) / 10);

      setState(() {
        _isScanning = false;
        _currentResult = picked;
        _confidence = simulatedConfidence;
        _scanHistory.insert(
          0,
          _ScanHistoryEntry(vocab: picked, confidence: simulatedConfidence),
        );
      });
    });
  }

  Future<void> _speakWord(String text) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 0.85,
          mode: VoiceMode.practice,
          contentId: 'object_scan_${text.hashCode}',
          contentType: 'object_scanner',
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', ..._vocabDb.categories];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สแกนวัตถุคำศัพท์ (Object Scanner)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey.shade800,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Category Filter ──
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white
                            : Colors.blueGrey.shade800,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.blueGrey.shade800,
                    backgroundColor: Colors.grey.shade200,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  );
                },
              ),
            ),
            Text(
              'โหมดจำลอง — เวอร์ชันนี้ยังไม่ใช้กล้องหรือ ML จริง',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // ── Simulation preview area ──
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyanAccent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: _isScanning
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.cyanAccent,
                                strokeWidth: 3,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'กำลังสุ่มตัวอย่างคำศัพท์...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _currentResult != null
                                    ? Icons.check_circle
                                    : Icons.center_focus_weak,
                                size: 64,
                                color: _currentResult != null
                                    ? Colors.greenAccent
                                    : Colors.cyanAccent,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _currentResult != null
                                    ? 'ผลจำลอง: ${_currentResult!.englishWord}'
                                    : 'กดปุ่มด้านล่างเพื่อสุ่มตัวอย่างคำศัพท์',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                  ),
                  // Scanning corners overlay
                  ..._buildScanCorners(),
                  if (_currentResult != null && !_isScanning)
                    Positioned(
                      top: 40,
                      left: 60,
                      right: 60,
                      bottom: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.greenAccent,
                            width: 2.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.greenAccent.withValues(alpha: 0.1),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: Colors.greenAccent,
                            child: Text(
                              'ตัวอย่าง: ${_currentResult!.mlLabel}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Simulation button ──
            ElevatedButton.icon(
              key: const ValueKey<String>('object-scanner-simulate-button'),
              onPressed: _isScanning ? null : _scanObject,
              icon: Icon(_isScanning ? Icons.hourglass_top : Icons.shuffle),
              label: Text(
                _isScanning ? 'กำลังสุ่ม...' : 'สุ่มตัวอย่างวัตถุ (โหมดจำลอง)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Stats Bar ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '📊 ฐานข้อมูล: ${_vocabDb.totalEntries} คำ | ${_vocabDb.categories.length} หมวด',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  '🔀 สุ่มแล้ว: ${_scanHistory.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),

            // ── Result Card ──
            if (_currentResult != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(_currentResult!, _confidence),
            ],

            // ── Scan History ──
            if (_scanHistory.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                '📋 ประวัติผลจำลอง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._scanHistory.take(10).map((entry) => _buildHistoryTile(entry)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ScannedVocabulary vocab, double confidence) {
    final confidencePercent = (confidence * 100).toStringAsFixed(1);
    final confidenceColor = confidence > 0.9
        ? Colors.green
        : confidence > 0.7
        ? Colors.orange
        : Colors.red;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Word + CEFR Badge + Confidence
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _cefrColor(vocab.cefrLevel),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vocab.cefrLevel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vocab.englishWord,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: confidenceColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: confidenceColor),
                  ),
                  child: Text(
                    '$confidencePercent%',
                    style: TextStyle(
                      color: confidenceColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Phonetic
            Text(
              vocab.phonetic,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),

            // Thai Translation
            Text(
              'คำแปล: ${vocab.thaiTranslation}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),

            // Category
            Text(
              '📁 หมวด: ${vocab.category}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const Divider(height: 20),

            // Example Sentence
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📖 ', style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: Text(
                      '"${vocab.exampleSentence}"',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.blue.shade900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Confidence Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ค่าความมั่นใจจำลอง: $confidencePercent%',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: confidence,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(confidenceColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _speakWord(vocab.englishWord),
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: const Text('ฟังเสียง'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _speakWord(vocab.exampleSentence),
                    icon: const Icon(Icons.record_voice_over, size: 18),
                    label: const Text('ฟังประโยค'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await SrsService().recordReview(
                          vocab.englishWord,
                          true,
                        );
                      } catch (_) {}
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '📥 บันทึก "${vocab.englishWord}" เข้าคลัง SRS Flashcards เรียบร้อย!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.bookmark_add, size: 18),
                    label: const Text('บันทึก'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(_ScanHistoryEntry entry) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _cefrColor(entry.vocab.cefrLevel),
          radius: 18,
          child: Text(
            entry.vocab.cefrLevel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          entry.vocab.englishWord,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          entry.vocab.thaiTranslation,
          style: const TextStyle(fontSize: 13),
        ),
        trailing: Text(
          '${(entry.confidence * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        dense: true,
        onTap: () {
          setState(() {
            _currentResult = entry.vocab;
            _confidence = entry.confidence;
          });
        },
      ),
    );
  }

  List<Widget> _buildScanCorners() {
    const cornerSize = 20.0;
    const cornerStroke = 3.0;
    const color = Colors.cyanAccent;

    return [
      Positioned(
        top: 8,
        left: 8,
        child: _corner(cornerSize, cornerStroke, color, true, true),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: _corner(cornerSize, cornerStroke, color, true, false),
      ),
      Positioned(
        bottom: 8,
        left: 8,
        child: _corner(cornerSize, cornerStroke, color, false, true),
      ),
      Positioned(
        bottom: 8,
        right: 8,
        child: _corner(cornerSize, cornerStroke, color, false, false),
      ),
    ];
  }

  Widget _corner(double size, double stroke, Color color, bool top, bool left) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CornerPainter(stroke, color, top, left)),
    );
  }

  Color _cefrColor(String level) {
    switch (level.toUpperCase()) {
      case 'A1':
        return Colors.green;
      case 'A2':
        return Colors.teal;
      case 'B1':
        return Colors.blue;
      case 'B2':
        return Colors.indigo;
      case 'C1':
        return Colors.purple;
      case 'C2':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }
}

class _ScanHistoryEntry {
  final ScannedVocabulary vocab;
  final double confidence;

  const _ScanHistoryEntry({required this.vocab, required this.confidence});
}

class _CornerPainter extends CustomPainter {
  final double stroke;
  final Color color;
  final bool top;
  final bool left;

  _CornerPainter(this.stroke, this.color, this.top, this.left);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
