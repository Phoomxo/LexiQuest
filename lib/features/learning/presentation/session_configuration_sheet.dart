import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../application/lesson_mode_registry.dart';
import '../application/session_configuration_policy.dart';
import '../domain/session_configuration.dart';
import '../domain/lesson_mode.dart';

final class SessionConfigurationPackOption {
  const SessionConfigurationPackOption({
    required this.identity,
    required this.label,
  });

  final ContentIdentity identity;
  final String label;
}

enum SessionConfigurationRecoveryDecision { resume, discard }

Future<SessionConfigurationRecoveryDecision?>
showSessionConfigurationRecoveryPrompt({
  required BuildContext context,
  bool canResume = true,
  required bool canDiscard,
}) => showDialog<SessionConfigurationRecoveryDecision>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('session-configuration-recovery-prompt'),
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    title: const Text('พบกิจกรรมที่เรียนค้างไว้'),
    content: Text(
      canResume
          ? 'เรียนต่อด้วยการตั้งค่าเดิม หรือทิ้งกิจกรรมที่ยังไม่จบแล้วเริ่มตั้งค่าใหม่'
          : 'กิจกรรมเดิมไม่มีการตั้งค่าที่บันทึกไว้ กรุณาทิ้งกิจกรรมเดิมก่อนเริ่มใหม่',
    ),
    actions: <Widget>[
      if (canResume)
        TextButton(
          key: const ValueKey('session-config-recovery-resume'),
          onPressed: () => Navigator.of(
            context,
          ).pop(SessionConfigurationRecoveryDecision.resume),
          child: const Text('เรียนต่อจากเดิม'),
        ),
      if (canDiscard)
        FilledButton(
          key: const ValueKey('session-config-recovery-discard'),
          onPressed: () => Navigator.of(
            context,
          ).pop(SessionConfigurationRecoveryDecision.discard),
          child: const Text('ทิ้งกิจกรรมเดิมแล้วเริ่มใหม่'),
        ),
    ],
  ),
);

class SessionConfigurationResetPrompt extends StatelessWidget {
  const SessionConfigurationResetPrompt({
    super.key,
    required this.error,
    required this.onReset,
    this.buttonLabel = 'ตั้งค่าใหม่',
  });

  final SessionConfigurationResetRequired error;
  final VoidCallback onReset;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('session-configuration-reset-prompt'),
    container: true,
    liveRegion: true,
    label: 'ต้องตั้งค่ากิจกรรมใหม่',
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'ตั้งค่ากิจกรรมใหม่',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(_resetMessage(error.reason)),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('session-config-reset'),
            onPressed: onReset,
            child: Text(buttonLabel),
          ),
        ],
      ),
    ),
  );
}

Future<SessionConfiguration?> showSessionConfigurationSheet({
  required BuildContext context,
  required LessonModeRegistration registration,
  required SessionConfigurationPolicy policy,
  required SessionConfigurationProtocolLimits limits,
  required String ownerId,
  required List<SessionConfigurationPackOption> packs,
  SessionConfiguration? initialConfiguration,
  SessionConfigurationResetRequired? initialResetRequired,
  bool initialResetCanUseDefaults = true,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await showModalBottomSheet<SessionConfiguration>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SessionConfigurationSheet(
      registration: registration,
      policy: policy,
      limits: limits,
      ownerId: ownerId,
      packs: packs,
      initialConfiguration: initialConfiguration,
      initialResetRequired: initialResetRequired,
      initialResetCanUseDefaults: initialResetCanUseDefaults,
    ),
  );
  if (context.mounted && previousFocus?.context != null) {
    previousFocus!.requestFocus();
  }
  return result;
}

class SessionConfigurationSheet extends StatefulWidget {
  const SessionConfigurationSheet({
    super.key,
    required this.registration,
    required this.policy,
    required this.limits,
    required this.ownerId,
    required this.packs,
    this.initialConfiguration,
    this.initialResetRequired,
    this.initialResetCanUseDefaults = true,
  });

  final LessonModeRegistration registration;
  final SessionConfigurationPolicy policy;
  final SessionConfigurationProtocolLimits limits;
  final String ownerId;
  final List<SessionConfigurationPackOption> packs;
  final SessionConfiguration? initialConfiguration;
  final SessionConfigurationResetRequired? initialResetRequired;
  final bool initialResetCanUseDefaults;

  @override
  State<SessionConfigurationSheet> createState() =>
      _SessionConfigurationSheetState();
}

class _SessionConfigurationSheetState extends State<SessionConfigurationSheet> {
  late SessionConfigurationCapabilities _capabilities;
  late SessionConfigurationDraft _draft;
  late final TextEditingController _itemCount;
  late final TextEditingController _timeLimitSeconds;
  SessionConfigurationResetRequired? _resetRequired;
  bool _submitting = false;
  bool _optionsExpanded = false;

  List<ContentIdentity> get _availablePackIdentities =>
      widget.packs.map((pack) => pack.identity).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _capabilities = const SessionConfigurationCapabilities(
      minimumItemCount: 1,
      maximumItemCount: 1,
      defaultItemCount: 1,
      directions: <SessionDirection>{SessionDirection.forward},
      difficulties: <SessionDifficulty>{SessionDifficulty.standard},
      maximumHintBudget: 0,
      supportsTimed: true,
      supportsUntimedAlternative: false,
      supportsPackSelection: false,
    );
    _draft = const SessionConfigurationDraft(
      itemCount: 1,
      direction: SessionDirection.forward,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: SessionTiming.timed(Duration(minutes: 10)),
    );
    _resetRequired = widget.initialResetRequired;
    try {
      final adapter = widget.registration.adapter;
      if (adapter is! SessionConfigurableLessonModeAdapter) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.unsupportedOption,
        );
      }
      _capabilities = adapter.sessionConfigurationCapabilities;
      _draft = widget.policy.defaultsFor(
        registration: widget.registration,
        limits: widget.limits,
      );
      if (widget.limits.pinnedPackIdentities.isNotEmpty &&
          widget.packs.isNotEmpty) {
        _draft = _draft.copyWith(packIdentity: widget.packs.first.identity);
      }
      final initial = widget.initialConfiguration;
      if (_resetRequired == null && initial != null) {
        _draft = widget.policy
            .revalidate(
              configuration: initial,
              registration: widget.registration,
              limits: widget.limits,
              ownerId: widget.ownerId,
              availablePackIdentities: _availablePackIdentities,
            )
            .draft;
      }
    } on SessionConfigurationResetRequired catch (error) {
      _resetRequired = error;
    }
    _itemCount = TextEditingController(text: '${_draft.itemCount}');
    _timeLimitSeconds = TextEditingController(
      text: '${_draft.timing.timedLimit?.inSeconds ?? 600}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reset = _resetRequired;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'ตั้งค่ากิจกรรมการเรียน',
      child: Material(
        key: const ValueKey('session-configuration-sheet'),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: reset == null ? _buildForm(context) : _buildReset(reset),
          ),
        ),
      ),
    );
  }

  Widget _buildReset(SessionConfigurationResetRequired reset) =>
      SessionConfigurationResetPrompt(
        error: reset,
        onReset: widget.initialResetCanUseDefaults
            ? _resetDefaults
            : () => Navigator.of(context).maybePop(),
        buttonLabel: widget.initialResetCanUseDefaults
            ? 'ตั้งค่าใหม่'
            : 'ปิดการตั้งค่า',
      );

  Widget _buildForm(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'ตั้งค่าก่อนเริ่มเรียน',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          MergeSemantics(
            child: Semantics(
              label: 'ปิดการตั้งค่าก่อนเริ่มเรียน',
              enabled: !_submitting,
              child: IconButton(
                key: const ValueKey('session-config-close'),
                tooltip: 'ปิดการตั้งค่าก่อนเริ่มเรียน',
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _buildSummary(),
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const ValueKey('session-config-start'),
        onPressed: _submitting ? null : _submit,
        icon: const Icon(Icons.play_arrow),
        label: Text(_submitting ? 'กำลังเริ่ม…' : 'เริ่มเรียน'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('session-options-toggle'),
        onPressed: _submitting
            ? null
            : () => setState(() {
                _optionsExpanded = !_optionsExpanded;
              }),
        icon: Icon(_optionsExpanded ? Icons.expand_less : Icons.tune),
        label: Text(_optionsExpanded ? 'ซ่อนตัวเลือก' : 'ปรับตัวเลือก'),
      ),
      if (_optionsExpanded) ...<Widget>[
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('session-item-count'),
          controller: _itemCount,
          onChanged: (_) => setState(() {}),
          enabled: !_submitting,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: 'จำนวนข้อ',
            helperMaxLines: 3,
            helperText: '$_minimumItems–$_maximumItems ข้อ ตามขอบเขตของกิจกรรม',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SessionDirection>(
          key: const ValueKey('session-direction'),
          initialValue: _draft.direction,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: 'ทิศทางคำถาม',
            helperMaxLines: 4,
            helperText: _directionDescription(_draft.direction),
          ),
          items: <DropdownMenuItem<SessionDirection>>[
            for (final value in _capabilities.directions)
              DropdownMenuItem(
                value: value,
                child: Text(_directionLabel(value)),
              ),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _draft = _draft.copyWith(direction: value));
                  }
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SessionDifficulty>(
          key: const ValueKey('session-difficulty'),
          initialValue: _draft.difficulty,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'ระดับความยาก'),
          items: <DropdownMenuItem<SessionDifficulty>>[
            for (final value in _capabilities.difficulties)
              DropdownMenuItem(
                value: value,
                child: Text(_difficultyLabel(value)),
              ),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _draft = _draft.copyWith(difficulty: value));
                  }
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const ValueKey('session-hint-budget'),
          initialValue: _draft.hintBudget,
          decoration: const InputDecoration(labelText: 'จำนวนคำใบ้'),
          items: <DropdownMenuItem<int>>[
            for (
              var value = 0;
              value <=
                  _capabilities.maximumHintBudget.clamp(
                    0,
                    widget.limits.maximumHintBudget,
                  );
              value += 1
            )
              DropdownMenuItem(value: value, child: Text('$value')),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _draft = _draft.copyWith(hintBudget: value));
                  }
                },
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            'การจับเวลา',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<SessionTimingKind>(
          groupValue: _draft.timing.kind,
          onChanged: (value) {
            if (!_submitting) _setTiming(value);
          },
          child: Column(
            children: <Widget>[
              const RadioListTile<SessionTimingKind>(
                key: ValueKey('session-timing-timed'),
                value: SessionTimingKind.timed,
                title: Text('จับเวลา'),
                subtitle: Text('ใช้เวลาสูงสุดตามขอบเขตที่กำหนด'),
              ),
              if (_capabilities.supportsUntimedAlternative &&
                  widget.limits.allowsUntimedAlternative)
                const RadioListTile<SessionTimingKind>(
                  key: ValueKey('session-timing-untimed'),
                  value: SessionTimingKind.untimedAlternative,
                  title: Text('ไม่แสดงเวลานับถอยหลัง'),
                  subtitle: Text('ยังจำกัดเวลาเรียนจริงตามขอบเขตที่กำหนด'),
                ),
            ],
          ),
        ),
        if (_draft.timing.kind == SessionTimingKind.timed) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('session-time-limit-seconds'),
            controller: _timeLimitSeconds,
            onChanged: (_) => setState(() {}),
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: 'เวลาสูงสุด (วินาที)',
              helperMaxLines: 3,
              helperText:
                  '${_durationLabel(widget.limits.minimumTimedSeconds)} ถึง '
                  '${_durationLabel(widget.limits.maximumTimedSeconds)} '
                  '(กรอกเป็นวินาที)',
            ),
          ),
        ],
        if (_capabilities.supportsPackSelection &&
            widget.packs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          DropdownButtonFormField<ContentIdentity>(
            key: const ValueKey('session-pack'),
            initialValue: _draft.packIdentity,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'ชุดเนื้อหาการเรียน'),
            items: <DropdownMenuItem<ContentIdentity>>[
              for (final pack in widget.packs)
                DropdownMenuItem(value: pack.identity, child: Text(pack.label)),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(
                        () => _draft = _draft.copyWith(packIdentity: value),
                      );
                    }
                  },
          ),
        ] else if (_capabilities.supportsPackSelection) ...<Widget>[
          const SizedBox(height: 24),
          const InputDecorator(
            key: ValueKey('session-pack'),
            decoration: InputDecoration(labelText: 'ชุดเนื้อหาการเรียน'),
            child: Text('คลังคำศัพท์ในเครื่อง'),
          ),
        ],
      ],
    ],
  );

  int get _minimumItems =>
      math.max(_capabilities.minimumItemCount, widget.limits.minimumItemCount);
  int get _maximumItems =>
      math.min(_capabilities.maximumItemCount, widget.limits.maximumItemCount);

  SessionConfigurationDraft get _requestedDraft => _draft.copyWith(
    itemCount: int.tryParse(_itemCount.text) ?? 0,
    timing: _draft.timing.kind == SessionTimingKind.timed
        ? SessionTiming.timed(
            Duration(seconds: int.tryParse(_timeLimitSeconds.text) ?? 0),
          )
        : _draft.timing,
  );

  Widget _buildSummary() {
    SessionConfiguration? preview;
    try {
      preview = widget.policy.validate(
        draft: _requestedDraft,
        registration: widget.registration,
        limits: widget.limits,
        ownerId: widget.ownerId,
        availablePackIdentities: _availablePackIdentities,
      );
    } on SessionConfigurationResetRequired {
      // Preview is read-only. Start retains the typed validation/reset flow.
    }
    String source = _capabilities.supportsPackSelection
        ? 'คลังคำศัพท์ในเครื่อง'
        : 'เนื้อหาที่เลือกสำหรับกิจกรรมนี้';
    if (_draft.packIdentity != null) {
      source = 'ชุดเนื้อหาที่เลือกยังไม่พร้อม';
      for (final pack in widget.packs) {
        if (pack.identity == _draft.packIdentity) source = pack.label;
      }
    }
    final timing = preview?.timing ?? _draft.timing;
    return Column(
      key: const ValueKey('session-config-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('เนื้อหา: $source'),
        const SizedBox(height: 12),
        Text(
          preview == null
              ? 'ต้องตรวจสอบตัวเลือกก่อนเริ่ม'
              : 'จำนวน ${preview.itemCount} ข้อ · เลือกได้ $_minimumItems–$_maximumItems ข้อ',
        ),
        const SizedBox(height: 12),
        Text(
          timing.isUntimedAlternative
              ? 'ไม่แสดงเวลานับถอยหลัง · เวลาเรียนจริงสูงสุด '
                    '${_durationLabel(timing.maximumActiveEffort!.inSeconds)}'
              : 'จับเวลา ${_durationLabel(timing.timedLimit!.inSeconds)}',
        ),
        const SizedBox(height: 12),
        Text(_directionDescription(_draft.direction)),
      ],
    );
  }

  String _directionDescription(SessionDirection direction) =>
      switch (widget.registration.mode) {
        LessonMode.meaningQuiz || LessonMode.matching => switch (direction) {
          SessionDirection.forward => 'ดูคำศัพท์แล้วเลือกความหมาย',
          SessionDirection.reverse => 'ดูความหมายแล้วเลือกคำศัพท์',
          SessionDirection.mixed => 'สลับคำศัพท์และความหมายเป็นโจทย์',
        },
        LessonMode.typedRecall =>
          'นึกแล้วพิมพ์จากคำศัพท์ ความหมาย หรือบริบทของโจทย์',
        LessonMode.definitionQuiz => 'อ่านคำอธิบายแล้วเลือกคำศัพท์',
        LessonMode.cloze => 'อ่านประโยคแล้วเติมคำในช่องว่าง',
        LessonMode.flashcard => 'ดูบัตรคำแล้วทบทวนคำตอบ',
        LessonMode.dictation => 'ฟังเสียงแล้วพิมพ์คำศัพท์',
        LessonMode.speaking => 'ดูโจทย์แล้วฝึกออกเสียง',
        LessonMode.shadowing => 'ฟังตัวอย่างแล้วพูดตามเสียง',
        LessonMode.cefrReading => 'อ่านบทความแล้วตอบตามกิจกรรม',
        LessonMode.sentenceScramble => 'เรียงคำให้เป็นประโยค',
        LessonMode.wordScramble => 'เรียงตัวอักษรให้เป็นคำศัพท์',
        LessonMode.associativeReading => 'อ่านเรื่องที่เชื่อมโยงคำศัพท์',
        LessonMode.handwritingScratchpad => 'ฝึกเขียนและตรวจคำตอบด้วยตนเอง',
      };

  static String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) return '$remainder วินาที';
    return remainder == 0 ? '$minutes นาที' : '$minutes นาที $remainder วินาที';
  }

  void _setTiming(SessionTimingKind? kind) {
    if (kind == null) return;
    final timing = switch (kind) {
      SessionTimingKind.timed => SessionTiming.timed(
        Duration(
          seconds:
              int.tryParse(_timeLimitSeconds.text) ??
              widget.limits.maximumTimedSeconds.clamp(60, 600),
        ),
      ),
      SessionTimingKind.untimedAlternative => SessionTiming.untimedAlternative(
        maximumActiveEffort: Duration(
          seconds: widget.limits.maximumUntimedActiveEffortSeconds,
        ),
      ),
    };
    setState(() => _draft = _draft.copyWith(timing: timing));
  }

  void _resetDefaults() {
    try {
      final defaults = widget.policy.defaultsFor(
        registration: widget.registration,
        limits: widget.limits,
      );
      setState(() {
        _resetRequired = null;
        _draft =
            widget.limits.pinnedPackIdentities.isNotEmpty &&
                widget.packs.isNotEmpty
            ? defaults.copyWith(packIdentity: widget.packs.first.identity)
            : defaults;
        _itemCount.text = '${_draft.itemCount}';
        _timeLimitSeconds.text =
            '${_draft.timing.timedLimit?.inSeconds ?? 600}';
      });
    } on SessionConfigurationResetRequired catch (error) {
      setState(() => _resetRequired = error);
    }
  }

  void _submit() {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final configuration = widget.policy.validate(
        draft: _requestedDraft,
        registration: widget.registration,
        limits: widget.limits,
        ownerId: widget.ownerId,
        availablePackIdentities: _availablePackIdentities,
      );
      Navigator.of(context).pop(configuration);
    } on SessionConfigurationResetRequired catch (error) {
      setState(() {
        _submitting = false;
        _resetRequired = error;
      });
    }
  }

  static String _directionLabel(SessionDirection value) => switch (value) {
    SessionDirection.forward => 'ทิศทางปกติ',
    SessionDirection.reverse => 'ย้อนทิศทาง',
    SessionDirection.mixed => 'สลับทิศทาง',
  };

  static String _difficultyLabel(SessionDifficulty value) => switch (value) {
    SessionDifficulty.supported => 'มีตัวช่วย',
    SessionDifficulty.standard => 'มาตรฐาน',
    SessionDifficulty.challenge => 'ท้าทาย',
  };

  @override
  void dispose() {
    _itemCount.dispose();
    _timeLimitSeconds.dispose();
    super.dispose();
  }
}

String _resetMessage(SessionConfigurationResetReason reason) =>
    switch (reason) {
      SessionConfigurationResetReason.unknownVersion =>
        'ไม่รองรับรุ่นการตั้งค่าของกิจกรรมนี้',
      SessionConfigurationResetReason.unsupportedOption =>
        'กิจกรรมนี้ไม่รองรับตัวเลือกบางรายการ',
      SessionConfigurationResetReason.invalidProtocol =>
        'ไม่สามารถอ่านขอบเขตการเรียนที่บันทึกไว้ได้',
      SessionConfigurationResetReason.staleProtocol =>
        'ขอบเขตการเรียนเปลี่ยนไปหลังจากตั้งค่ากิจกรรมนี้',
      SessionConfigurationResetReason.ownerDrift =>
        'ผู้เรียนปัจจุบันเปลี่ยนไปหลังจากตั้งค่ากิจกรรมนี้',
      SessionConfigurationResetReason.packDrift =>
        'ไม่พบชุดเนื้อหาการเรียนรุ่นที่เลือกไว้',
      SessionConfigurationResetReason.modeDrift =>
        'รูปแบบกิจกรรมเปลี่ยนไปหลังจากตั้งค่า',
      SessionConfigurationResetReason.modeUnavailable =>
        'กิจกรรมนี้ไม่พร้อมใช้งานแล้ว',
      SessionConfigurationResetReason.tampered =>
        'ไม่สามารถตรวจสอบความถูกต้องของการตั้งค่าที่บันทึกไว้ได้',
    };
