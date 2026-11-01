import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../application/learning_profile_use_cases.dart';
import '../domain/learning_profile.dart';

class LearningProfileEditorScreen extends StatefulWidget {
  const LearningProfileEditorScreen({
    super.key,
    required this.profile,
    this.onboarding = false,
  });
  final LearningProfileUseCases profile;
  final bool onboarding;

  @override
  State<LearningProfileEditorScreen> createState() =>
      _LearningProfileEditorScreenState();
}

class _LearningProfileEditorScreenState
    extends State<LearningProfileEditorScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _goal = TextEditingController();
  final _date = TextEditingController();
  final _minutes = TextEditingController();
  final _interests = <String>{};
  StreamSubscription<String?>? _owners;
  LearningProfileSnapshot? _snapshot;
  LearningProfileChange? _pending;
  String? _owner;
  String? _status;
  var _generation = 0;
  var _readRevision = 0;
  var _loading = true;
  var _busy = false;
  var _dirty = false;
  AppDependencies? _boundDependencies;
  var _dependenciesBound = false;
  var _retired = false;

  static const _interestLabels = {
    'daily': 'ชีวิตประจำวัน',
    'study': 'การเรียน',
    'exam': 'การสอบ',
    'work': 'การทำงาน',
    'travel': 'การเดินทาง',
    'culture': 'วัฒนธรรม',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _observe();
  }

  void _observe() {
    _owners = widget.profile.watchActiveOwnerId().listen(
      _ownerChanged,
      onError: (Object _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final replaced =
        _dependenciesBound && !identical(dependencies, _boundDependencies);
    _dependenciesBound = true;
    _boundDependencies = dependencies;
    if (replaced ||
        (dependencies != null &&
            !identical(dependencies.learningProfile, widget.profile))) {
      _retired = true;
      unawaited(_owners?.cancel());
      _ownerChanged(null);
    }
  }

  @override
  void didUpdateWidget(LearningProfileEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile == widget.profile) return;
    _generation++;
    unawaited(_owners?.cancel());
    _ownerChanged(null);
    _observe();
  }

  void _ownerChanged(String? owner) {
    if (!mounted || (_retired && owner != null)) return;
    final generation = ++_generation;
    setState(() {
      _owner = owner;
      _snapshot = null;
      _pending = null;
      _busy = false;
      _loading = owner != null;
      _status = _retired
          ? 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดกลับไปเปิดแผนการเรียนใหม่'
          : owner == null
          ? 'ไม่พบผู้เรียนที่พร้อมใช้งาน'
          : null;
      _goal.clear();
      _date.clear();
      _minutes.clear();
      _interests.clear();
      _dirty = false;
    });
    if (owner != null) unawaited(_load(owner, generation));
  }

  bool _current(String owner, int generation) =>
      mounted && !_retired && _owner == owner && _generation == generation;

  Future<void> _load(String owner, int generation) async {
    final revision = ++_readRevision;
    bool current() => _current(owner, generation) && revision == _readRevision;
    try {
      final snapshot = await widget.profile.load(
        expectedOwnerId: owner,
        stillCurrent: current,
      );
      if (!current()) return;
      final draft = snapshot.profile?.draft;
      setState(() {
        _snapshot = snapshot;
        _goal.text = draft?.goalText ?? '';
        _date.text = draft?.targetDate?.toString() ?? '';
        _minutes.text = draft?.dailyMinutes?.toString() ?? '';
        _interests
          ..clear()
          ..addAll(draft?.interestCodes ?? const []);
        _pending = null;
        _dirty = false;
        _status = null;
        _loading = false;
      });
    } catch (_) {
      if (!current()) return;
      setState(() {
        _loading = false;
        _status = 'อ่านแผนการเรียนไม่ได้ ลองใหม่ได้โดยไม่เปลี่ยนข้อมูล';
      });
    }
  }

  void _edited() {
    _readRevision++;
    setState(() {
      _pending = null;
      _dirty = true;
      _status = null;
    });
  }

  Future<void> _save({bool skip = false}) async {
    final snapshot = _snapshot;
    final owner = _owner;
    if (_busy || snapshot == null || owner == null) return;
    if (!skip &&
        _pending == null &&
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    _readRevision++;
    final generation = _generation;
    try {
      _pending ??= widget.profile.prepareChange(
        snapshot: snapshot,
        draft: skip
            ? LearningProfileDraft(
                onboardingState: LearningOnboardingState.skipped,
              )
            : LearningProfileDraft(
                onboardingState: LearningOnboardingState.completed,
                goalText: _goal.text,
                targetDate: _date.text.trim().isEmpty
                    ? null
                    : LearningCivilDate.parse(_date.text.trim()),
                dailyMinutes: _minutes.text.trim().isEmpty
                    ? null
                    : int.parse(_minutes.text.trim()),
                interestCodes: _interests.toList(),
              ),
        stillCurrent: () => _current(owner, generation),
      );
      setState(() {
        _busy = true;
        _status = 'กำลังบันทึกแผนการเรียน';
      });
      final saved = await widget.profile.save(_pending!);
      if (!_current(owner, generation)) return;
      setState(() {
        _snapshot = LearningProfileSnapshot(ownerId: owner, profile: saved);
        _pending = null;
        _dirty = false;
        _status = skip
            ? 'ข้ามการตั้งค่าแล้ว แก้ไขภายหลังได้'
            : 'บันทึกแผนการเรียนแล้ว';
      });
      if (widget.onboarding && mounted) Navigator.of(context).pop();
    } on LearningProfileException catch (error) {
      if (!_current(owner, generation)) return;
      setState(() {
        _status = switch (error.code) {
          LearningProfileFailureCode.conflict =>
            'แผนถูกแก้ไขจากที่อื่นแล้ว โหลดข้อมูลล่าสุดก่อนบันทึก',
          LearningProfileFailureCode.ownerChanged =>
            'ผู้เรียนเปลี่ยนแล้ว เปิดหน้านี้ใหม่เพื่อแก้ไข',
          LearningProfileFailureCode.invalid =>
            'ตรวจเป้าหมาย วันที่ และเวลาเรียนอีกครั้ง',
          LearningProfileFailureCode.unavailable =>
            'ยังยืนยันการบันทึกไม่ได้ กดลองบันทึกเดิมอีกครั้งได้',
        };
      });
    } catch (_) {
      if (!_current(owner, generation)) return;
      setState(
        () => _status = 'ยังยืนยันการบันทึกไม่ได้ กดลองบันทึกเดิมอีกครั้งได้',
      );
    } finally {
      if (_current(owner, generation)) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_dirty) {
      final owner = _owner;
      if (owner != null) unawaited(_load(owner, _generation));
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_owners?.cancel());
    _goal.dispose();
    _date.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _snapshot?.profile?.draft.targetDate;
    final days = target?.daysFrom(
      LearningCivilDate.fromDateTime(DateTime.now()),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          widget.onboarding ? 'วางแผนการเรียนของคุณ' : 'แผนและเป้าหมายการเรียน',
        ),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านแผนการเรียน',
                ),
              )
            : Form(
                key: _form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'เลือกตั้งค่าได้ตามต้องการ ข้ามหรือแก้ไขภายหลังได้',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'การตั้งค่านี้ไม่เปิดการแจ้งเตือนหรือบันทึกเวลาเรียนให้อัตโนมัติ',
                      ),
                      if (_snapshot != null) ...[
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const ValueKey('learning-profile-goal'),
                          controller: _goal,
                          enabled: !_busy && _pending == null,
                          maxLength: 120,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'เป้าหมายการเรียน',
                            hintText: 'เช่น อ่านบทความภาษาอังกฤษ',
                          ),
                          onChanged: (_) => _edited(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('learning-profile-date'),
                          controller: _date,
                          enabled: !_busy && _pending == null,
                          keyboardType: TextInputType.datetime,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'วันที่เป้าหมายหรือวันสอบ',
                            helperText:
                                'ปี ค.ศ.-เดือน-วัน เช่น 2026-12-31 เว้นว่างเพื่อล้าง',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            try {
                              LearningCivilDate.parse(value.trim());
                              return null;
                            } catch (_) {
                              return 'ใส่วันที่ที่มีจริงในรูปแบบ YYYY-MM-DD';
                            }
                          },
                          onChanged: (_) => _edited(),
                        ),
                        if (days != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days == 0
                                  ? 'ถึงวันเป้าหมายวันนี้'
                                  : days > 0
                                  ? 'เหลือ $days วันถึงเป้าหมาย'
                                  : 'ผ่านวันเป้าหมายแล้ว ${-days} วัน',
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('learning-profile-minutes'),
                          controller: _minutes,
                          enabled: !_busy && _pending == null,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'เวลาที่อยากเรียนต่อวัน (นาที)',
                            helperText: '1 ถึง 180 นาที หรือเว้นว่าง',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final minutes = int.tryParse(value.trim());
                            return minutes == null ||
                                    minutes < 1 ||
                                    minutes > 180
                                ? 'ใส่จำนวนเต็มระหว่าง 1 ถึง 180'
                                : null;
                          },
                          onChanged: (_) => _edited(),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'หัวข้อที่สนใจ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in _interestLabels.entries)
                              FilterChip(
                                label: Text(entry.value),
                                selected: _interests.contains(entry.key),
                                onSelected: _busy || _pending != null
                                    ? null
                                    : (selected) {
                                        if (selected) {
                                          _interests.add(entry.key);
                                        } else {
                                          _interests.remove(entry.key);
                                        }
                                        _edited();
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const ValueKey('learning-profile-save'),
                          onPressed: _busy ? null : _save,
                          child: Text(
                            _pending == null
                                ? 'บันทึกแผนการเรียน'
                                : 'ลองบันทึกเดิมอีกครั้ง',
                          ),
                        ),
                        if (widget.onboarding)
                          TextButton(
                            key: const ValueKey('learning-profile-skip'),
                            onPressed: _busy || _pending != null
                                ? null
                                : () => _save(skip: true),
                            child: const Text('ข้ามการตั้งค่า'),
                          ),
                      ],
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_status!),
                          ),
                        ),
                      if (_owner != null && !_busy)
                        OutlinedButton(
                          onPressed: () {
                            unawaited(_load(_owner!, _generation));
                          },
                          child: const Text('โหลดแผนล่าสุด'),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
