import '../../learning/application/unified_lesson_controller.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_session_state.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/adventure_session_plan.dart';

final class AdventureLearningLaunch {
  AdventureLearningLaunch({
    required this.plan,
    required this.command,
    required List<ContentIdentity> content,
  }) : content = List<ContentIdentity>.unmodifiable(content);

  final AdventureSessionPlanV1 plan;
  final LessonStartCommand command;
  final List<ContentIdentity> content;

  AdventureOriginContextV1 get transientOrigin => plan.origin;
}

/// Validates Adventure metadata, then delegates unchanged canonical commands
/// and submissions to the existing Learning controller.
final class AdventureLearningBridge {
  const AdventureLearningBridge();

  AdventureLearningLaunch prepare({
    required AdventureSessionPlanV1 plan,
    required String activeOwnerId,
    required String sessionId,
    required DateTime startedAtUtc,
  }) {
    if (plan.ownerId != activeOwnerId ||
        plan.configuration.ownerId != activeOwnerId) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.ownerMismatch,
      );
    }
    if (!startedAtUtc.isUtc ||
        startedAtUtc.microsecondsSinceEpoch %
                Duration.microsecondsPerMillisecond !=
            0 ||
        sessionId.isEmpty ||
        sessionId != sessionId.trim()) {
      throw ArgumentError('Adventure learning launch is not canonical.');
    }
    if (plan.content.length != plan.configuration.itemCount ||
        plan.content.any(
          (identity) =>
              !_sha256.hasMatch(plan.contentChecksumsSha256[identity.id] ?? ''),
        )) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.unresolvedContent,
      );
    }
    return AdventureLearningLaunch(
      plan: plan,
      command: LessonStartCommand(
        mode: plan.mode,
        sessionId: sessionId,
        startedAtUtc: startedAtUtc,
        itemCount: plan.content.length,
        ownerId: plan.ownerId,
        configuration: plan.configuration,
      ),
      content: plan.content,
    );
  }

  Future<void> start({
    required AdventureLearningLaunch launch,
    required UnifiedLessonController controller,
    required SessionConfigurationRevalidator revalidateConfiguration,
  }) async {
    if (controller.state.mode != launch.plan.mode) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.incompatibleConfiguration,
      );
    }
    controller.bindSessionConfiguration(
      launch.plan.configuration,
      revalidate: revalidateConfiguration,
    );
    await controller.start(launch.command);
  }

  Future<AnswerRecordResult> submit({
    required UnifiedLessonController controller,
    required LessonSubmission submission,
  }) => controller.submit(submission);
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
