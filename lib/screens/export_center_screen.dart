import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/anki_dictionary_exporter_service.dart';
import '../services/pdf_glossary_exporter_service.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  final PdfGlossaryExporterService _pdfService =
      const PdfGlossaryExporterService();
  String _previewContent = '';
  String _activeTab = 'anki';

  final List<VocabularyCardExport> _sampleCards = const [
    VocabularyCardExport(
      word: 'perseverance',
      ipa: '/ˌpɜːsɪˈvɪərəns/',
      translation: 'ความอุตสาหะ พากเพียร',
      exampleSentence: 'Success requires dedication and perseverance.',
    ),
    VocabularyCardExport(
      word: 'resilience',
      ipa: '/rɪˈzɪliəns/',
      translation: 'ความยืดหยุ่น ฟื้นตัวไว',
      exampleSentence: 'Mental resilience helps overcome daily challenges.',
    ),
    VocabularyCardExport(
      word: 'meticulous',
      ipa: '/mɪˈtɪkjələs/',
      translation: 'พิถีพิถัน ละเอียดถี่ถ้วน',
      exampleSentence: 'She paid meticulous attention to research details.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _generateAnkiExport();
  }

  void _generateAnkiExport() {
    setState(() {
      _activeTab = 'anki';
      _previewContent = AnkiDictionaryExporterService.exportToAnkiTxt(
        _sampleCards,
      );
    });
  }

  void _generatePdfGlossary() {
    final list = _sampleCards
        .map(
          (c) => {
            'word': c.word,
            'translation': c.translation,
            'example': c.exampleSentence,
          },
        )
        .toList();
    setState(() {
      _activeTab = 'pdf';
      _previewContent = _pdfService.generateGlossaryDocument(list);
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _previewContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 คัดลอกข้อมูลไปยัง คลิปบอร์ด เรียบร้อย!'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Export Center (ส่งออกสมุดศัพท์ & ข้อมูลวิจัย)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Export Format Segmented Buttons
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'anki',
                  label: Text('Anki Deck'),
                  icon: Icon(Icons.style, size: 16),
                ),
                ButtonSegment(
                  value: 'pdf',
                  label: Text('PDF Glossary'),
                  icon: Icon(Icons.picture_as_pdf, size: 16),
                ),
              ],
              selected: {_activeTab},
              onSelectionChanged: (Set<String> newSelection) {
                final selected = newSelection.first;
                if (selected == 'anki') _generateAnkiExport();
                if (selected == 'pdf') _generatePdfGlossary();
              },
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ตัวอย่างไฟล์ที่สร้าง ($_activeTab.txt):',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('คัดลอกไฟล์'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _previewContent,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 13,
                      color: Colors.cyanAccent,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
