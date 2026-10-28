import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'ai_tutor_settings_screen.dart';

/// Compatibility route for older navigation links. New code should use
/// [AiTutorSettingsScreen].
@Deprecated('Use AiTutorSettingsScreen')
class GeminiSettingsScreen extends AiTutorSettingsScreen {
  const GeminiSettingsScreen({super.key, AiTutorController? geminiTutor})
    : super(aiTutor: geminiTutor);
}
