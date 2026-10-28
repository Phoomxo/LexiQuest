import 'package:flutter/material.dart';

import '../features/learning/application/flashcard_mode_adapter.dart';
import '../features/learning/application/session_configuration_policy.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/session_configuration_sheet.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'mastery_dashboard_screen.dart';
import 'srs_flashcards_screen.dart';

class WeaknessClinicScreen extends StatefulWidget {
  const WeaknessClinicScreen({super.key, this.loader});

  final ProgressLoader? loader;

  @override
  State<WeaknessClinicScreen> createState() => _WeaknessClinicScreenState();
}

class _WeaknessClinicScreenState extends State<WeaknessClinicScreen> {
  Future<ProgressSnapshot>? _load;
  bool _openingSrs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    _load = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : loader();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('คลินิกจุดอ่อน')),
      body: FutureBuilder<ProgressSnapshot>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _WeaknessMessage(
              'ไม่สามารถอ่านประวัติคำตอบในเครื่องได้',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final progress = snapshot.data!;
          if (progress.sampleSize == 0) {
            return const _WeaknessMessage(
              'ยังไม่มีคำตอบสำหรับวิเคราะห์\nจำนวนตัวอย่าง: 0',
            );
          }
          if (progress.weaknesses.isEmpty) {
            return _WeaknessMessage(
              'ยังไม่พบคำที่ตอบผิด\nจำนวนตัวอย่าง: ${progress.sampleSize}',
            );
          }
          return _WeaknessBody(progress, onReviewDue: _openConfiguredSrs);
        },
      ),
    );
  }

  Future<void> _openConfiguredSrs() async {
    if (_openingSrs) return;
    setState(() => _openingSrs = true);
    try {
      final dependencies = AppDependenciesScope.maybeOf(context);
      final registration = dependencies?.lessonModes?.resolve(
        LessonMode.flashcard,
      );
      final features = dependencies?.features;
      final owners = dependencies?.localOwners;
      final protocols = dependencies?.sessionConfigurationProtocols;
      final configurations = dependencies?.sessionConfigurations;
      final createController = dependencies?.createLessonController;
      if (registration == null ||
          registration.adapter is! FlashcardModeAdapter ||
          features?.isEnabled(Feature.srs) != true ||
          owners == null ||
          protocols == null ||
          configurations == null ||
          createController == null ||
          dependencies?.learning == null) {
        if (mounted) await _pushUnavailableSrs(features);
        return;
      }

      late final String ownerId;
      late final SessionConfigurationProtocolLimits limits;
      SessionConfiguration? initialConfiguration;
      try {
        ownerId = (await owners.getOrCreateActiveOwner()).id;
        SessionConfigurationPolicy.requireCanonical(ownerId, 'ownerId');
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.ownerDrift,
        );
      }
      try {
        limits = await protocols.resolveForOwner(ownerId);
      } on SessionConfigurationResetRequired {
        rethrow;
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.invalidProtocol,
        );
      }
      try {
        initialConfiguration = await configurations.read(
          ownerId: ownerId,
          mode: LessonMode.flashcard,
        );
      } on SessionConfigurationResetRequired {
        rethrow;
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
      if (!mounted) return;
      const policy = SessionConfigurationPolicy();
      final configuration = await showSessionConfigurationSheet(
        context: context,
        registration: registration,
        policy: policy,
        limits: limits,
        ownerId: ownerId,
        packs: const [],
        initialConfiguration: initialConfiguration,
      );
      if (configuration == null || !mounted) return;

      Future<SessionConfiguration> revalidate(
        SessionConfiguration candidate,
      ) async {
        final live = AppDependenciesScope.maybeOf(context);
        final liveRegistration = live?.lessonModes?.resolve(
          LessonMode.flashcard,
        );
        if (liveRegistration == null ||
            !identical(liveRegistration.adapter, registration.adapter) ||
            live?.features.isEnabled(Feature.srs) != true) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.modeUnavailable,
          );
        }
        late final String liveOwnerId;
        late final SessionConfigurationProtocolLimits liveLimits;
        try {
          liveOwnerId = (await live!.localOwners!.getOrCreateActiveOwner()).id;
          SessionConfigurationPolicy.requireCanonical(liveOwnerId, 'ownerId');
        } catch (_) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.ownerDrift,
          );
        }
        try {
          liveLimits = await live.sessionConfigurationProtocols!
              .resolveForOwner(liveOwnerId);
        } on SessionConfigurationResetRequired {
          rethrow;
        } catch (_) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.invalidProtocol,
          );
        }
        return policy.revalidate(
          configuration: candidate,
          registration: liveRegistration,
          limits: liveLimits,
          ownerId: liveOwnerId,
          availablePackIdentities: const [],
        );
      }

      final refreshed = await revalidate(configuration);
      try {
        await configurations.save(
          refreshed,
          updatedAtUtc: DateTime.now().toUtc(),
        );
      } on SessionConfigurationResetRequired {
        rethrow;
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
          'The validated configuration could not be persisted.',
        );
      }
      if (!mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/weakness-srs',
          builder: (_) => UnifiedLessonModeHost(
            adapter: registration.adapter,
            createController: createController,
            feature: Feature.srs,
            featureRegistry: features,
            learning: dependencies!.learning,
            configuration: refreshed,
            revalidateConfiguration: revalidate,
            builder: (_) =>
                SrsFlashcardsScreen(sessionConfiguration: refreshed),
          ),
        ),
      );
    } on SessionConfigurationResetRequired catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.promptMessage)));
      }
    } finally {
      if (mounted) setState(() => _openingSrs = false);
    }
  }

  Future<void> _pushUnavailableSrs(FeatureRegistry? features) =>
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/weakness-srs',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.srs,
            registry: features,
            builder: (_) => const ProductionFeatureUnavailable(
              feature: Feature.srs,
              reason: ProductionFeatureUnavailableReason.missingDependency,
            ),
          ),
        ),
      );
}

class _WeaknessBody extends StatelessWidget {
  const _WeaknessBody(this.progress, {required this.onReviewDue});

  final ProgressSnapshot progress;
  final VoidCallback onReviewDue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'จัดอันดับจากสัดส่วนคำตอบผิด จำนวนตัวอย่างทั้งหมด '
            '${progress.sampleSize} • อัลกอริทึมเวอร์ชัน '
            '${progress.algorithmVersion}',
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: progress.weaknesses.length,
            itemBuilder: (context, index) {
              final item = progress.weaknesses[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(item.spelling),
                  subtitle: Text(
                    '${item.meaning}\nตอบผิด ${item.incorrectCount}/${item.sampleSize} ครั้ง '
                    '(${(item.errorRate * 100).toStringAsFixed(0)}%)',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: progress.dueReviewCount == 0 ? null : onReviewDue,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.event_repeat),
            label: Text(
              progress.dueReviewCount == 0
                  ? 'ยังไม่มีคำที่ถึงกำหนดทบทวน'
                  : 'ทบทวนคำที่ถึงกำหนด (${progress.dueReviewCount})',
            ),
          ),
        ),
      ],
    );
  }
}

class _WeaknessMessage extends StatelessWidget {
  const _WeaknessMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
