import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/lexi_vision_accessibility_service.dart';

void main() {
  test('announceObject formats speech text with IPA and translation', () {
    final result = LexiVisionAccessibilityService.announceObject('cup');

    expect(result.labelWord, 'cup');
    expect(result.ipaPhonetic, '/kʌp/');
    expect(result.translation, 'แก้วน้ำ');
    expect(result.cefrLevel, 'A1');
    expect(result.speechText, contains('CUP'));
  });

  test('announceObject handles unknown labels gracefully', () {
    final result = LexiVisionAccessibilityService.announceObject('telescope');

    expect(result.labelWord, 'telescope');
    expect(result.speechText, contains('TELESCOPE'));
  });
}
