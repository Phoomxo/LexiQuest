import 'package:flutter/material.dart';

import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class PhoneticSymbol {
  final String ipa;
  final String exampleWord;
  final String description;

  const PhoneticSymbol({
    required this.ipa,
    required this.exampleWord,
    required this.description,
  });
}

class PhoneticExplorerScreen extends StatefulWidget {
  final VoiceUseCases? voice;

  const PhoneticExplorerScreen({super.key, this.voice});

  @override
  State<PhoneticExplorerScreen> createState() => _PhoneticExplorerScreenState();
}

class _PhoneticExplorerScreenState extends State<PhoneticExplorerScreen>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<PhoneticExplorerScreen> {
  VoiceUseCases? _voiceProvider;
  String? _selectedIpa;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voiceProvider;

  final List<PhoneticSymbol> _phonetics = const [
    PhoneticSymbol(
      ipa: '/æ/',
      exampleWord: 'cat',
      description: 'เสียง แอ สั้น',
    ),
    PhoneticSymbol(
      ipa: '/θ/',
      exampleWord: 'think',
      description: 'เสียง ธ์ แลบลิ้นแตะฟันหน้า',
    ),
    PhoneticSymbol(
      ipa: '/ʃ/',
      exampleWord: 'she',
      description: 'เสียง ชู ห่อปาก',
    ),
    PhoneticSymbol(
      ipa: '/ʒ/',
      exampleWord: 'vision',
      description: 'เสียง ฌ สั่นในคอ',
    ),
    PhoneticSymbol(
      ipa: '/ŋ/',
      exampleWord: 'sing',
      description: 'เสียง ง นาสิกขึ้นจมูก',
    ),
    PhoneticSymbol(
      ipa: '/iː/',
      exampleWord: 'see',
      description: 'เสียง อี ยาว',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _voiceProvider = widget.voice ?? dependencies?.voice;
    refreshRouteVoiceSession();
  }

  Future<void> _speakWord(PhoneticSymbol symbol) async {
    final session = routeVoiceSession;
    if (session == null) return;
    setState(() {
      _selectedIpa = symbol.ipa;
    });
    try {
      await session.speak(
        VoiceRequest.create(
          text: symbol.exampleWord,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 0.8,
          mode: VoiceMode.practice,
          contentId: symbol.exampleWord,
          contentType: 'phonetic_explorer',
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_voiceProvider == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.voice,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สำรวจสัทอักษร IPA (Phonetic Explorer)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal.shade800,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    Icon(Icons.record_voice_over, color: Colors.teal, size: 36),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'แตะที่สัทอักษรเพื่อฟังเสียงตัวอย่างตามหลักสรีรศาสตร์การออกเสียง',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemCount: _phonetics.length,
                itemBuilder: (context, index) {
                  final item = _phonetics[index];
                  final isSelected = _selectedIpa == item.ipa;
                  return InkWell(
                    onTap: () => _speakWord(item),
                    child: Card(
                      elevation: isSelected ? 4 : 1,
                      color: isSelected ? Colors.teal.shade100 : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.teal
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.ipa,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ex: "${item.exampleWord}"',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
