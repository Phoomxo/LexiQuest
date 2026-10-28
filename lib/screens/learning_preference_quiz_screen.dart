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
    final useCases = _useCases(context);
    _preference ??= useCases?.read().then((value) {
      _goal = value.goal;
      _activity = value.activityPreference;
      _minutes.text = value.availableMinutesPerDay.toString();
      return value;
    });
  }

  bool _mutationAllowed() {
    final registry = AppDependenciesScope.maybeOf(context)?.features;
    return registry?.isEnabled(Feature.studyPlanning) ??
        widget.useCases != null;
  }

  Future<void> _save(LearnerPreferencesUseCases useCases) async {
    if (_submitting) return;
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null || minutes < 1 || minutes > 240) {
      setState(() => _message = 'Enter between 1 and 240 minutes.');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await useCases.save(
        goal: _goal,
        availableMinutesPerDay: minutes,
        activityPreference: _activity,
        mutationAllowed: _mutationAllowed,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = 'Preferences saved.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = _mutationAllowed()
            ? 'Preferences were not saved. Try again.'
            : 'Learning preferences are unavailable.';
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
        body: const Center(
          child: Text('Learning preferences are unavailable.'),
        ),
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
            return const Center(
              child: Text('Learning preferences are unavailable.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Choose editable defaults for your next learning plan.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<LearnerPreferenceGoal>(
                key: const ValueKey<String>('learning-preferences/goal'),
                initialValue: _goal,
                decoration: const InputDecoration(labelText: 'Goal'),
                items: LearnerPreferenceGoal.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
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
                  labelText: 'Available minutes per day',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LearnerActivityPreference>(
                key: const ValueKey<String>(
                  'learning-preferences/activity-preference',
                ),
                initialValue: _activity,
                decoration: const InputDecoration(
                  labelText: 'Preferred activity',
                ),
                items: LearnerActivityPreference.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
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
                onPressed: _submitting ? null : () => _save(useCases),
                child: Text(_submitting ? 'Saving…' : 'Save preferences'),
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
