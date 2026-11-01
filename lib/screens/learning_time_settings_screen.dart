import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../features/learning_time/presentation/recorded_time_view.dart';

class LearningTimeSettingsScreen extends StatefulWidget {
  const LearningTimeSettingsScreen({
    super.key,
    required this.time,
    required this.expectedOwnerId,
  });
  final LearningTimeUseCases? time;
  final String expectedOwnerId;
  @override
  State<LearningTimeSettingsScreen> createState() =>
      _LearningTimeSettingsScreenState();
}

class _LearningTimeSettingsScreenState
    extends State<LearningTimeSettingsScreen> {
  late LearningTimeBinding _binding;
  bool _dependenciesReady = false;
  int? _ownerGeneration;
  int _operationGeneration = 0;
  int _lastVisibilityGeneration = 0;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _binding.syncVisibility();
  }

  @override
  void didUpdateWidget(LearningTimeSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.time, oldWidget.time) ||
        widget.expectedOwnerId != oldWidget.expectedOwnerId) {
      _binding.removeListener(_bindingChanged);
      _binding.dispose();
      _bind();
    }
  }

  bool _visible() =>
      _dependenciesReady &&
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _bind() {
    _operationGeneration++;
    _ownerGeneration = widget.time?.ownerGeneration;
    _busy = false;
    _failed = false;
    final wasReady = _dependenciesReady;
    _dependenciesReady = false;
    _binding = LearningTimeBinding(
      time: widget.time,
      expectedOwnerId: widget.expectedOwnerId,
      visible: _visible,
    );
    _dependenciesReady = wasReady;
    _lastVisibilityGeneration = _binding.visibilityGeneration;
    _binding.addListener(_bindingChanged);
  }

  void _bindingChanged() {
    if (!mounted) return;
    if (!_binding.current ||
        _lastVisibilityGeneration != _binding.visibilityGeneration) {
      _operationGeneration++;
      _busy = false;
      _failed = false;
    }
    _lastVisibilityGeneration = _binding.visibilityGeneration;
    setState(() {});
  }

  bool _capturedCurrent({
    required LearningTimeBinding binding,
    required LearningTimeUseCases? time,
    required String owner,
    required int? ownerGeneration,
    required int visibility,
  }) =>
      mounted &&
      identical(_binding, binding) &&
      identical(widget.time, time) &&
      widget.expectedOwnerId == owner &&
      _ownerGeneration == ownerGeneration &&
      time?.ownerGeneration == ownerGeneration &&
      time?.ownerId == owner &&
      binding.current &&
      binding.visibilityGeneration == visibility;

  Future<void> _setEnabled(
    bool enabled, {
    required LearningTimeBinding binding,
    required LearningTimeUseCases time,
    required String owner,
    required int? ownerGeneration,
    required int visibility,
    required int preferenceRevision,
  }) async {
    bool current() => _capturedCurrent(
      binding: binding,
      time: time,
      owner: owner,
      ownerGeneration: ownerGeneration,
      visibility: visibility,
    );
    if (!current() || _busy || time.preference?.revision != preferenceRevision) {
      return;
    }
    final operation = ++_operationGeneration;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await time.setEnabled(
      enabled,
      expectedOwnerId: owner,
      stillCurrent: () =>
          current() && time.preference?.revision == preferenceRevision,
    );
    if (!current() || operation != _operationGeneration) return;
    setState(() {
      _busy = false;
      _failed = result == null;
    });
  }

  @override
  void dispose() {
    _operationGeneration++;
    _binding.removeListener(_bindingChanged);
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _binding.syncVisibility();
    final binding = _binding;
    final time = widget.time;
    final owner = widget.expectedOwnerId;
    final ownerGeneration = _ownerGeneration;
    final visibility = binding.visibilityGeneration;
    final thai = Localizations.localeOf(context).languageCode == 'th';
    final preference = binding.current ? time?.preference : null;
    final pendingSetting =
        binding.current &&
        time!.pendingState == LearningTimePendingState.preference;
    final available = preference != null && !_busy && !pendingSetting;
    final margin = MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? BackButton(
                onPressed: () {
                  if (!mounted ||
                      !identical(_binding, binding) ||
                      !binding.hostVisible ||
                      binding.visibilityGeneration != visibility) {
                    return;
                  }
                  Navigator.of(context).pop();
                },
              )
            : null,
        title: Text(thai ? 'เวลาการเรียนในเครื่อง' : 'Local learning time'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.all(margin),
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    thai ? 'บันทึกเวลาจากการโต้ตอบ' : 'Record interaction time',
                  ),
                  subtitle: Text(
                    thai
                        ? 'เก็บเฉพาะในเครื่องและแยกตามผู้ใช้'
                        : 'Stored on this device, separately for each user',
                  ),
                  value: preference?.enabled ?? false,
                  onChanged: available
                      ? (value) {
                          unawaited(
                            _setEnabled(
                              value,
                              binding: binding,
                              time: time!,
                              owner: owner,
                              ownerGeneration: ownerGeneration,
                              visibility: visibility,
                              preferenceRevision: preference.revision,
                            ),
                          );
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  thai
                      ? 'เริ่มต้นปิดไว้ เลือกเปิดเพื่อบันทึกช่วงที่มีการโต้ตอบต่อเนื่องกับกิจกรรมการเรียน เมื่อปิดแล้ว ประวัติที่บันทึกสำเร็จยังอ่านได้'
                      : 'Off by default. Enable to save confirmed interaction windows during learning. Turning this off keeps previously saved history readable.',
                ),
                const SizedBox(height: 12),
                Text(
                  thai
                      ? 'ไม่รวมการรอ AI การขอสิทธิ์ การบันทึกคำตอบ หรือช่วงที่ออกจากหน้าฝึก การอ่านเงียบเกิน 60 วินาทีอาจนับเวลาได้น้อยกว่าจริง'
                      : 'AI, permission and answer-saving waits, and time away from the activity, are excluded. Reading without input for over 60 seconds may be undercounted.',
                ),
                const SizedBox(height: 12),
                Text(
                  thai
                      ? 'ใช้ดูพฤติกรรมการใช้งาน ไม่ได้ใช้วัดสมาธิ ความชำนาญ หรือผลการเรียน'
                      : 'This describes interaction behavior, not attention, mastery or learning outcomes.',
                ),
                if (_busy ||
                    pendingSetting ||
                    _failed ||
                    preference == null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      preference == null
                          ? (thai
                                ? 'การตั้งค่าไม่พร้อมสำหรับผู้ใช้รายนี้'
                                : 'Settings are unavailable for this user')
                          : (_busy || pendingSetting)
                          ? (thai
                                ? 'การตั้งค่ายังรอยืนยัน'
                                : 'Setting change awaiting confirmation')
                          : (thai
                                ? 'ยังยืนยันการเปลี่ยนแปลงไม่ได้ ลองอีกครั้งได้'
                                : 'The change is not confirmed yet. You can retry.'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                RecordedTimeView(
                  time: time,
                  expectedOwnerId: owner,
                  target: const OwnerTimeRead(),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
