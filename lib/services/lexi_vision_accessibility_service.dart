class VisionAnnouncement {
  final String labelWord;
  final String ipaPhonetic;
  final String translation;
  final String cefrLevel;
  final String speechText;
  final String hapticFeedbackType;

  const VisionAnnouncement({
    required this.labelWord,
    required this.ipaPhonetic,
    required this.translation,
    required this.cefrLevel,
    required this.speechText,
    required this.hapticFeedbackType,
  });
}

/// LexiVision Inclusive Accessibility Engine (Universal Design for Learning - UDL Standard).
class LexiVisionAccessibilityService {
  const LexiVisionAccessibilityService();

  static const Map<String, Map<String, String>> _objectDict = {
    'cup': {'ipa': '/kʌp/', 'th': 'แก้วน้ำ', 'cefr': 'A1'},
    'table': {'ipa': '/ˈteɪbl/', 'th': 'โต๊ะ', 'cefr': 'A1'},
    'chair': {'ipa': '/tʃeər/', 'th': 'เก้าอี้', 'cefr': 'A1'},
    'book': {'ipa': '/bʊk/', 'th': 'หนังสือ', 'cefr': 'A1'},
    'phone': {'ipa': '/fəʊn/', 'th': 'โทรศัพท์', 'cefr': 'A2'},
    'laptop': {'ipa': '/ˈlæptɒp/', 'th': 'แล็ปท็อป', 'cefr': 'A2'},
  };

  /// Generates a speech announcement for a detected camera label
  static VisionAnnouncement announceObject(String detectedLabel) {
    final cleanLabel = detectedLabel.trim().toLowerCase();
    final info =
        _objectDict[cleanLabel] ??
        {'ipa': '/$cleanLabel/', 'th': cleanLabel, 'cefr': 'B1'};

    final speech =
        'ตรวจพบ ${cleanLabel.toUpperCase()} ระดับ ${info['cefr']} ออกเสียงว่า ${info['ipa']} แปลว่า ${info['th']}';

    return VisionAnnouncement(
      labelWord: cleanLabel,
      ipaPhonetic: info['ipa']!,
      translation: info['th']!,
      cefrLevel: info['cefr']!,
      speechText: speech,
      hapticFeedbackType: 'heavy_impact',
    );
  }
}
