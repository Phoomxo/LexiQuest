import 'package:flutter/material.dart';

import '../features/preferences/application/learner_preferences_use_cases.dart';
import '../features/preferences/domain/learner_preferences.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';

final class LearningPreferenceQuizScreen extends StatefulWidget {
  const LearningPreferenceQuizScreen({super.key, this.useCases});

  final LearnerPreferencesUseCases? useCases;

  @override
  State<LearningPreferenceQuizScreen> createState() =>
      _LearningPreferenceQuizScreenState();
}

final class _LearningPreferenceQuizScreenState
    extends State<LearningPreferenceQuizScreen> {
  final TextEditingController _minutes = TextEditingController();
  Future<LearnerPreferences>? _preference;
  LearnerPreferencesUseCases? _activeUseCases;
  String? _loadedOwnerId;
  int _generation = 0;
  LearnerPreferenceGoal _goal = LearnerPreferenceGoal.balancedGrowth;
  LearnerActivityPreference _activity = LearnerActivityPreference.mixedPractice;
  bool _submitting = false;
  String? _message;

  LearnerPreferencesUseCases? _useCases(BuildContext context) =>
      widget.useCases ??
      AppDependenciesScope.maybeOf(context)?.learnerPreferences;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindUseCases();
  }

  @override
  void didUpdateWidget(covariant LearningPreferenceQuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindUseCases();
  }

  void _bindUseCases() {
    final useCases = _useCases(context);
    if (identical(useCases, _activeUseCases) && _preference != null) return;
    _activeUseCases = useCases;
    final generation = ++_generation;
    _loadedOwnerId = null;
    _submitting = false;
    _message = null;
    _preference = useCases?.read().then((value) {
      if (!_isCurrent(generation, useCases)) return value;
      _loadedOwnerId = value.ownerId;
      _goal = value.goal;
      _activity = value.activityPreference;
      _minutes.text = value.availableMinutesPerDay.toString();
      return value;
    });
  }

  bool _isCurrent(int generation, LearnerPreferencesUseCases? useCases) =>
      mounted &&
      generation == _generation &&
      identical(_activeUseCases, useCases);

  bool _mutationAllowed() {
    final registry = AppDependenciesScope.maybeOf(context)?.features;
    return registry?.isEnabled(Feature.studyPlanning) ??
        widget.useCases != null;
  }

  Future<void> _save(
    LearnerPreferencesUseCases useCases,
    int generation,
  ) async {
    if (_submitting || !_isCurrent(generation, useCases)) return;
    final ownerId = _loadedOwnerId;
    if (ownerId == null) return;
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null || minutes < 1 || minutes > 240) {
      setState(() => _message = 'กรุณาระบุเวลาตั้งแต่ 1 ถึง 240 นาที');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await useCases.save(
        expectedOwnerId: ownerId,
        goal: _goal,
        availableMinutesPerDay: minutes,
        activityPreference: _activity,
        mutationAllowed: () =>
            _isCurrent(generation, useCases) && _mutationAllowed(),
      );
      if (!_isCurrent(generation, useCases)) return;
      setState(() {
        _submitting = false;
        _message = 'บันทึกการตั้งค่าการเรียนแล้ว';
      });
    } on Object {
      if (!_isCurrent(generation, useCases)) return;
      setState(() {
        _submitting = false;
        _message = _mutationAllowed()
            ? 'บันทึกการตั้งค่าไม่สำเร็จ กรุณาลองอีกครั้ง'
            : 'ยังไม่พร้อมตั้งค่าการเรียน';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final useCases = _useCases(context);
    if (useCases == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            NavigationGlossary.require(
              'study-planning/learning-preferences',
            ).fullThaiLabel,
          ),
        ),
        body: const Center(child: Text('ยังไม่พร้อมตั้งค่าการเรียน')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NavigationGlossary.require(
            'study-planning/learning-preferences',
          ).fullThaiLabel,
        ),
      ),
      body: FutureBuilder<LearnerPreferences>(
        future: _preference,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('ยังไม่พร้อมตั้งค่าการเรียน'));
          }
          final generation = _generation;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'เลือกเป้าหมายและกิจกรรมสำหรับแผนการเรียนครั้งถัดไป คุณเปลี่ยนภายหลังได้',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<LearnerPreferenceGoal>(
                key: const ValueKey<String>('learning-preferences/goal'),
                initialValue: _goal,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'เป้าหมาย'),
                items: LearnerPreferenceGoal.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(switch (value) {
                          LearnerPreferenceGoal.balancedGrowth =>
                            'พัฒนาทักษะอย่างสมดุล',
                          LearnerPreferenceGoal.examPreparation => 'เตรียมสอบ',
                          LearnerPreferenceGoal.conversationConfidence =>
                            'สนทนาอย่างมั่นใจ',
                          LearnerPreferenceGoal.vocabularyGrowth =>
                            'เพิ่มคลังคำศัพท์',
                        }),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) _goal = value;
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>(
                  'learning-preferences/available-minutes',
                ),
                controller: _minutes,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'เวลาเรียนต่อวัน (นาที)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LearnerActivityPreference>(
                key: const ValueKey<String>(
                  'learning-preferences/activity-preference',
                ),
                initialValue: _activity,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'กิจกรรมที่ชอบ'),
                items: LearnerActivityPreference.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(switch (value) {
                          LearnerActivityPreference.mixedPractice =>
                            'ฝึกหลายรูปแบบ',
                          LearnerActivityPreference.quiz => 'แบบทดสอบ',
                          LearnerActivityPreference.speaking => 'ฝึกพูด',
                          LearnerActivityPreference.reading => 'ฝึกอ่าน',
                          LearnerActivityPreference.vocabulary =>
                            'เรียนคำศัพท์',
                        }),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) _activity = value;
                      },
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey<String>('learning-preferences/save'),
                onPressed: _submitting
                    ? null
                    : () => _save(useCases, generation),
                child: Text(_submitting ? 'กำลังบันทึก…' : 'บันทึกการตั้งค่า'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }
}
