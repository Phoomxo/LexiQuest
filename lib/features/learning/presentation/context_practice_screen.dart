import 'package:flutter/material.dart';
import '../../../screens/fill_in_the_blanks_screen.dart';
import '../../learning_packs/application/personal_set_activities.dart';
import '../application/cloze_mode_adapter.dart';
import '../application/current_activity_evidence.dart';
import '../application/learning_use_cases.dart';

/// Context-specific entry into the canonical cloze presentation/lifecycle.
final class ContextPracticeScreen extends StatelessWidget {
  const ContextPracticeScreen({
    super.key,
    required this.launch,
    required this.learning,
    required this.evidence,
  });
  final PersonalSetActivityLaunch launch;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  @override
  Widget build(BuildContext context) => FillInTheBlanksScreen(
    contextLaunch: launch,
    learning: learning,
    evidenceAdapter: evidence,
    modeAdapter: const ClozeModeAdapter(),
  );
}
