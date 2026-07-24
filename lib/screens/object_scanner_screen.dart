import 'package:flutter/material.dart';

class DetectedObject {
  final String englishWord;
  final String thaiTranslation;
  final String cefrLevel;
  final IconData icon;

  const DetectedObject({
    required this.englishWord,
    required this.thaiTranslation,
    required this.cefrLevel,
    required this.icon,
  });
}

class ObjectScannerScreen extends StatefulWidget {
  const ObjectScannerScreen({super.key});

  @override
  State<ObjectScannerScreen> createState() => _ObjectScannerScreenState();
}

class _ObjectScannerScreenState extends State<ObjectScannerScreen> {
  bool _isScanning = false;
  DetectedObject? _detectedObject;

  final List<DetectedObject> _simulatedObjects = const [
    DetectedObject(
      englishWord: 'laptop',
      thaiTranslation: 'คอมพิวเตอร์พกพา',
      cefrLevel: 'A2',
      icon: Icons.laptop,
    ),
    DetectedObject(
      englishWord: 'coffee',
      thaiTranslation: 'กาแฟ',
      cefrLevel: 'A1',
      icon: Icons.local_cafe,
    ),
    DetectedObject(
      englishWord: 'headphone',
      thaiTranslation: 'หูฟัง',
      cefrLevel: 'B1',
      icon: Icons.headphones,
    ),
    DetectedObject(
      englishWord: 'book',
      thaiTranslation: 'หนังสือ',
      cefrLevel: 'A1',
      icon: Icons.book,
    ),
  ];

  void _scanSimulatedObject() {
    setState(() {
      _isScanning = true;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        final shuffled = _simulatedObjects.toList()..shuffle();
        setState(() {
          _isScanning = false;
          _detectedObject = shuffled.first;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สแกนวัตถุคำศัพท์ (Object Scanner)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey.shade800,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
              child: Center(
                child: _isScanning
                    ? const CircularProgressIndicator(color: Colors.cyan)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _detectedObject?.icon ?? Icons.center_focus_weak,
                            size: 80,
                            color: Colors.cyan,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _detectedObject != null
                                ? 'สแกนพบ: ${_detectedObject!.englishWord}'
                                : 'ส่องกล้องไปยังวัตถุในห้องแล้วกดสแกน',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanSimulatedObject,
              icon: const Icon(Icons.camera_alt),
              label: const Text('จำลองสแกนวัตถุตรงหน้า'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            if (_detectedObject != null) ...[
              const Divider(height: 30),
              Card(
                color: Colors.blue.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      _detectedObject!.cefrLevel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    _detectedObject!.englishWord,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  subtitle: Text(
                    'คำแปล: ${_detectedObject!.thaiTranslation}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
