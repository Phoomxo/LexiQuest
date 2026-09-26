import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/ai_tutor/presentation/menu_action_binding.dart';
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
  LearnerPreferences? _lastConfirmed;
  String _assistanceStatus = 'ready';
  bool _active = false;
  bool _exited = false;
  bool _reading = false;
  bool _pickerOpen = false;
  bool _pickerCovered = false;
  bool _dirty = false;
  bool _uncertain = false;
  AppDependencies? _dependencies;
  StreamSubscription<({String ownerId, String? firebaseUid})?>?
  _ownerSubscription;
  int _ownerEpoch = 0;

  bool get _visible =>
      !_exited &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  void _edited() {
    _dirty = true;
    _assistanceStatus = 'editing';
    _message = null;
  }

  Map<String, Object?> _confirmedValue(LearnerPreferences value) => {
    'goal': value.goal.name,
    'activity': value.activityPreference.name,
    'minutes': value.availableMinutesPerDay,
  };

  String _assistanceContext() {
    final minutes = int.tryParse(_minutes.text);
    return jsonEncode({
      'status': _assistanceStatus,
      'purpose':
          'Learning preferences for planning; not measured proficiency or a learning score.',
      'manualSaveRequired': true,
      'draft': {
        'goal': _goal.name,
        'activity': _activity.name,
        'minutes': minutes != null && minutes >= 1 && minutes <= 240
            ? minutes
            : null,
      },
      'lastConfirmed': _lastConfirmed == null
          ? null
          : _confirmedValue(_lastConfirmed!),
    });
  }

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

  void _clearDraft() {
    _loadedOwnerId = null;
    _lastConfirmed = null;
    _goal = LearnerPreferenceGoal.balancedGrowth;
    _activity = LearnerActivityPreference.mixedPractice;
    _minutes.clear();
    _dirty = false;
    _uncertain = false;
    _message = null;
    _assistanceStatus = 'ready';
  }

  void _retire() {
    _pickerOpen = false;
    _pickerCovered = false;
    ++_generation;
    _reading = false;
    if (_submitting) _uncertain = true;
    _submitting = false;
  }

  void _bindUseCases() {
    final useCases = _useCases(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final changed =
        !identical(useCases, _activeUseCases) ||
        !identical(dependencies?.progress, _dependencies?.progress);
    final active = _visible;
    // The form's own dropdown route is a selection, not leaving the form.
    // Its callbacks still require the form to be current after the route closes.
    if (!changed &&
        _pickerOpen &&
        !active &&
        TickerMode.valuesOf(context).enabled) {
      _pickerCovered = true;
      return;
    }
    if (active && _pickerCovered) {
      _pickerOpen = false;
      _pickerCovered = false;
    }
    if (!changed && active == _active && _preference != null) return;
    _retire();
    if (changed) _clearDraft();
    _activeUseCases = useCases;
    _dependencies = dependencies;
    _active = active;
    final epoch = ++_ownerEpoch;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    if (!_active) return;
    _load();
    final progress = dependencies?.progress;
    if (useCases != null &&
        progress != null &&
        identical(progress.owners, useCases.owners)) {
      _ownerSubscription = progress.watchProfileOwner().listen(
        (owner) {
          if (!mounted || epoch != _ownerEpoch || !_active || _exited) return;
          if (owner?.ownerId == _loadedOwnerId ||
              (_loadedOwnerId == null && _reading))
            return;
          setState(() {
            _active = _visible;
            _retire();
            _clearDraft();
            _preference = null;
            // Removing the retired form also retires its owned picker. Resume
            // reads only once the underlying route is current again.
            if (_active) _load();
          });
          final generation = _generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Disposing a dropdown removes its route during this frame; that
            // removal need not trigger another dependency notification here.
            if (mounted &&
                !_exited &&
                generation == _generation &&
                !_active &&
                _visible)
              setState(_bindUseCases);
          });
        },
        onError: (Object error, StackTrace stack) {
          if (!mounted || epoch != _ownerEpoch || _exited) return;
          setState(() {
            _retire();
            // Keep the private draft while identity is temporarily unreadable.
            // The error view exposes no context; retry revalidates its owner.
            _preference = Future<LearnerPreferences>.error(error, stack);
            _preference!.ignore();
          });
        },
      );
    }
  }

  Future<LearnerPreferences> _readConfirmed(
    LearnerPreferencesUseCases useCases,
  ) async {
    final value = await useCases.read();
    final owner = await useCases.owners.getOrCreateActiveOwner();
    if (owner.id != value.ownerId) throw StateError('preference owner changed');
    return value;
  }

  bool _matchesDraft(LearnerPreferences value) =>
      value.goal == _goal &&
      value.activityPreference == _activity &&
      value.availableMinutesPerDay == int.tryParse(_minutes.text);

  void _accept(LearnerPreferences value) {
    if (_loadedOwnerId != value.ownerId) _clearDraft();
    _loadedOwnerId = value.ownerId;
    _lastConfirmed = value;
    if (!_dirty) {
      _goal = value.goal;
      _activity = value.activityPreference;
      _minutes.text = value.availableMinutesPerDay.toString();
    }
    if (_uncertain) {
      final saved = _matchesDraft(value);
      _assistanceStatus = saved ? 'saved' : 'saveFailed';
      _message = saved
          ? 'บันทึกการตั้งค่าการเรียนแล้ว'
          : 'ยังไม่พบค่าที่ต้องการบันทึก ร่างยังอยู่ คุณลองบันทึกอีกครั้งได้';
      if (saved) _dirty = false;
      _uncertain = false;
    }
  }

  void _load() {
    final useCases = _activeUseCases;
    if (useCases == null) return;
    final generation = ++_generation;
    _reading = true;
    _preference = Future<LearnerPreferences>.sync(
      () => _readConfirmed(useCases),
    );
    _preference!.then<void>(
      (value) {
        if (!_isCurrent(generation, useCases)) return;
        _reading = false;
        _accept(value);
      },
      onError: (Object _, StackTrace __) {
        if (_isCurrent(generation, useCases)) _reading = false;
      },
    );
  }

  void _retry(int generation, LearnerPreferencesUseCases useCases) {
    if (!_isCurrent(generation, useCases) || _reading || _submitting) return;
    setState(_load);
  }

  bool _isCurrent(int generation, LearnerPreferencesUseCases? useCases) =>
      mounted &&
      _active &&
      _visible &&
      generation == _generation &&
      identical(_activeUseCases, useCases);

  void _exit() {
    _exited = true;
    _ownerEpoch++;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _retire();
  }

  bool _mutationAllowed() {
    final registry = AppDependenciesScope.maybeOf(context)?.features;
    return registry?.isEnabled(Feature.studyPlanning) ??
        widget.useCases != null;
  }

  Future<void> _save(
    LearnerPreferencesUseCases useCases,
    int generation,
  ) async {
    if (_submitting ||
        _reading ||
        _uncertain ||
        !_isCurrent(generation, useCases))
      return;
    final ownerId = _loadedOwnerId;
    if (ownerId == null) return;
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null || minutes < 1 || minutes > 240) {
      setState(() {
        _assistanceStatus = 'invalidDraft';
        _message = 'กรุณาระบุเวลาตั้งแต่ 1 ถึง 240 นาที';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _assistanceStatus = 'saving';
      _message = null;
    });
    try {
      final confirmed = await useCases.save(
        expectedOwnerId: ownerId,
        goal: _goal,
        availableMinutesPerDay: minutes,
        activityPreference: _activity,
        mutationAllowed: () =>
            _isCurrent(generation, useCases) && _mutationAllowed(),
      );
      if (!_isCurrent(generation, useCases)) return;
      final currentOwner = await useCases.owners.getOrCreateActiveOwner();
      if (!_isCurrent(generation, useCases)) return;
      if (currentOwner.id != ownerId || confirmed.ownerId != ownerId) {
        throw StateError('preference owner changed after save');
      }
      setState(() {
        _submitting = false;
        _lastConfirmed = confirmed;
        _dirty = false;
        _assistanceStatus = 'saved';
        _message = 'บันทึกการตั้งค่าการเรียนแล้ว';
      });
    } on Object {
      if (!_isCurrent(generation, useCases)) return;
      // The write may have committed before acknowledgement failed. Read only;
      // never repeat a mutation or claim failure until the durable value is known.
      setState(() {
        _submitting = false;
        _uncertain = true;
        _assistanceStatus = 'checking';
        _message = 'ยังยืนยันการบันทึกไม่ได้ กำลังอ่านค่าล่าสุด';
        _load();
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
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_exited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            NavigationGlossary.require(
              'study-planning/learning-preferences',
            ).fullThaiLabel,
          ),
        ),
        body: !_active || _exited
            ? const SizedBox.shrink()
            : FutureBuilder<LearnerPreferences>(
                key: ValueKey(_generation),
                future: _preference,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final generation = _generation;
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ยังไม่พร้อมตั้งค่าการเรียน'),
                            if (_uncertain)
                              const Text(
                                'ยังยืนยันการบันทึกไม่ได้ ลองอ่านค่าล่าสุดโดยไม่บันทึกซ้ำ ร่างยังอยู่',
                              ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => _retry(generation, useCases),
                              child: const Text('ลองใหม่'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final generation = _generation;
                  return MenuActionBinding(
                    id: 'study-planning/learning-preferences/context',
                    label:
                        'Learning preference draft and last confirmed values',
                    ownerId: _loadedOwnerId,
                    onInvoke: null,
                    readValue: _loadedOwnerId == null
                        ? null
                        : _assistanceContext(),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Text(
                          'เลือกเป้าหมายและกิจกรรมสำหรับแผนการเรียนครั้งถัดไป คุณเปลี่ยนภายหลังได้',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<LearnerPreferenceGoal>(
                          key: const ValueKey<String>(
                            'learning-preferences/goal',
                          ),
                          initialValue: _goal,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: const InputDecoration(
                            labelText: 'เป้าหมาย',
                          ),
                          items: LearnerPreferenceGoal.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(switch (value) {
                                    LearnerPreferenceGoal.balancedGrowth =>
                                      'พัฒนาทักษะอย่างสมดุล',
                                    LearnerPreferenceGoal.examPreparation =>
                                      'เตรียมสอบ',
                                    LearnerPreferenceGoal
                                        .conversationConfidence =>
                                      'สนทนาอย่างมั่นใจ',
                                    LearnerPreferenceGoal.vocabularyGrowth =>
                                      'เพิ่มคลังคำศัพท์',
                                  }),
                                ),
                              )
                              .toList(growable: false),
                          onTap: () {
                            if (mounted &&
                                !_exited &&
                                _active &&
                                generation == _generation &&
                                identical(useCases, _activeUseCases) &&
                                !_submitting)
                              _pickerOpen = true;
                          },
                          onChanged: _submitting
                              ? null
                              : (value) {
                                  if (value != null &&
                                      !_submitting &&
                                      _isCurrent(generation, useCases)) {
                                    setState(() {
                                      _goal = value;
                                      _edited();
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey<String>(
                            'learning-preferences/available-minutes',
                          ),
                          controller: _minutes,
                          onChanged: (_) {
                            if (!_submitting &&
                                _isCurrent(generation, useCases))
                              setState(_edited);
                          },
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
                          decoration: const InputDecoration(
                            labelText: 'กิจกรรมที่ชอบ',
                          ),
                          items: LearnerActivityPreference.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(switch (value) {
                                    LearnerActivityPreference.mixedPractice =>
                                      'ฝึกหลายรูปแบบ',
                                    LearnerActivityPreference.quiz =>
                                      'แบบทดสอบ',
                                    LearnerActivityPreference.speaking =>
                                      'ฝึกพูด',
                                    LearnerActivityPreference.reading =>
                                      'ฝึกอ่าน',
                                    LearnerActivityPreference.vocabulary =>
                                      'เรียนคำศัพท์',
                                  }),
                                ),
                              )
                              .toList(growable: false),
                          onTap: () {
                            if (mounted &&
                                !_exited &&
                                _active &&
                                generation == _generation &&
                                identical(useCases, _activeUseCases) &&
                                !_submitting)
                              _pickerOpen = true;
                          },
                          onChanged: _submitting
                              ? null
                              : (value) {
                                  if (value != null &&
                                      !_submitting &&
                                      _isCurrent(generation, useCases)) {
                                    setState(() {
                                      _activity = value;
                                      _edited();
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          key: const ValueKey<String>(
                            'learning-preferences/save',
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _save(useCases, generation),
                          child: Text(
                            _submitting ? 'กำลังบันทึก…' : 'บันทึกการตั้งค่า',
                          ),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Semantics(liveRegion: true, child: Text(_message!)),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _exit();
    _minutes.dispose();
    super.dispose();
  }
}
