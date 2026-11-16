import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/gemini/domain/gemini_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

class GeminiSettingsScreen extends StatefulWidget {
  const GeminiSettingsScreen({super.key, this.geminiTutor});

  final GeminiTutorController? geminiTutor;

  @override
  State<GeminiSettingsScreen> createState() => _GeminiSettingsScreenState();
}

class _GeminiSettingsScreenState extends State<GeminiSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  GeminiTutorController? _tutor;
  GeminiScope? _visibleScope;
  bool _resolved = false;
  StreamSubscription<int>? _scopeSubscription;
  int _epoch = 0;
  GeminiCancellation? _cancellation;
  bool _loading = true;
  bool _saving = false;
  bool _hasKey = false;
  bool _providerConsent = false;
  bool _summaryConsent = false;
  String? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolved =
        widget.geminiTutor ??
        AppDependenciesScope.maybeOf(context)?.geminiTutor;
    if (_resolved && identical(resolved, _tutor)) return;
    _resolved = true;
    _epoch += 1;
    _cancellation?.cancel();
    _keyController.clear();
    _hasKey = false;
    _providerConsent = false;
    _summaryConsent = false;
    _saving = false;
    _notice = null;
    unawaited(_scopeSubscription?.cancel());
    _tutor = resolved;
    _visibleScope = resolved?.scope;
    _scopeSubscription = resolved?.invalidations.listen((_) => _scopeChanged());
    _load();
  }

  bool _current(int epoch, int? scopeEpoch) =>
      mounted &&
      epoch == _epoch &&
      scopeEpoch == _tutor?.epoch &&
      _visibleScope == _tutor?.scope;

  void _scopeChanged() {
    if (!mounted) return;
    _epoch += 1;
    _visibleScope = _tutor?.scope;
    _cancellation?.cancel();
    _cancellation = null;
    setState(() {
      _keyController.clear();
      _saving = false;
      _hasKey = false;
      _providerConsent = false;
      _summaryConsent = false;
      _error = null;
      _notice = null;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final tutor = _tutor;
    final originalScope = tutor?.scope;
    final epoch = _epoch;
    final scopeEpoch = tutor?.epoch;
    if (tutor == null) {
      setState(() {
        _loading = false;
        _error = 'ระบบ Gemini ยังไม่พร้อมใช้งานบนแอปเวอร์ชันนี้';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await tutor.loadSettings();
      if (!_current(epoch, scopeEpoch)) return;
      setState(() {
        _hasKey = status.hasKey;
        _providerConsent = status.providerConsent;
        _summaryConsent = status.shareLearningSummary;
      });
    } on GeminiException catch (error) {
      if (_current(epoch, scopeEpoch) && tutor.scope == originalScope) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_current(epoch, scopeEpoch)) setState(() => _loading = false);
    }
  }

  Future<void> _validateAndSave() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'กรุณากรอกรหัสเชื่อมต่อ Gemini');
      return;
    }
    final cancellation = GeminiCancellation();
    final epoch = _epoch;
    final scopeEpoch = tutor.epoch;
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.configure(
        key: key,
        providerConsent: _providerConsent,
        shareLearningSummary: _summaryConsent,
        cancellation: cancellation,
      );
      if (!_current(epoch, scopeEpoch) || cancellation.isCancelled) return;
      _keyController.clear();
      setState(() {
        _hasKey = true;
        _notice = 'ตรวจสอบและเก็บรหัสในที่จัดเก็บปลอดภัยแล้ว';
      });
    } on GeminiException catch (error) {
      if (_current(epoch, scopeEpoch)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_current(epoch, scopeEpoch)) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _saveConsents() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final bump = _providerConsent ? 0 : 1;
    final epoch = _epoch + bump;
    final scopeEpoch = tutor.epoch + bump;
    final originalScope = tutor.scope;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final operation = tutor.updateConsents(
        providerConsent: _providerConsent,
        shareLearningSummary: _summaryConsent,
      );
      await operation;
      if (_current(epoch, scopeEpoch) && tutor.scope == originalScope) {
        setState(() => _notice = 'ใช้การยินยอมสำหรับรอบนี้แล้ว');
      }
    } on GeminiException catch (error) {
      if (_current(epoch, scopeEpoch) && tutor.scope == originalScope) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_current(epoch, scopeEpoch)) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final epoch = _epoch;
    final scopeEpoch = tutor.epoch;
    final originalScope = tutor.scope;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรหัสเชื่อมต่อ Gemini?'),
        content: const Text(
          'ผู้ช่วยฝึกภาษาจะเรียก Gemini ไม่ได้จนกว่าจะเพิ่มและตรวจสอบรหัสใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบรหัส'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current(epoch, scopeEpoch)) return;
    final resultEpoch = epoch + 1;
    final resultScopeEpoch = scopeEpoch + 1;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final operation = tutor.removeKey();
      await operation;
      if (!_current(resultEpoch, resultScopeEpoch) ||
          tutor.scope != originalScope) {
        return;
      }
      _keyController.clear();
      setState(() {
        _hasKey = false;
        _providerConsent = false;
        _summaryConsent = false;
        _notice = 'ลบรหัสเชื่อมต่อและปิดการส่งข้อมูลไป Gemini แล้ว';
      });
    } on GeminiException catch (error) {
      if (_current(resultEpoch, resultScopeEpoch) &&
          tutor.scope == originalScope) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_current(resultEpoch, resultScopeEpoch)) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _epoch += 1;
    unawaited(_scopeSubscription?.cancel());
    _cancellation?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'เชื่อมต่อ Gemini'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'กำลังโหลดการตั้งค่า Gemini',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      _hasKey
                          ? 'สถานะ: มีรหัสเชื่อมต่อที่ตรวจสอบแล้ว'
                          : 'สถานะ: ยังไม่มีรหัสเชื่อมต่อ',
                      key: const ValueKey<String>('gemini-key-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'รหัสเชื่อมต่อ (API key) เก็บแบบเข้ารหัสด้วย Android Keystore '
                      'และไม่บันทึกในฐานข้อมูลหรือบันทึกระบบ ควรใช้รหัสแยกและ'
                      'ตั้งเพดานงบใน Google AI Studio',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey<String>('gemini-key-input'),
                      controller: _keyController,
                      enabled: !_saving,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _hasKey
                            ? 'รหัสเชื่อมต่อ Gemini ใหม่'
                            : 'รหัสเชื่อมต่อ Gemini',
                        helperText: _hasKey
                            ? 'กรอกเฉพาะเมื่อต้องการเปลี่ยนรหัส'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'รหัสเชื่อมต่อแยกตามบัญชี ต้องเปิดการยินยอมใหม่เมื่อเปิดแอปหรือเปลี่ยนบัญชี',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _providerConsent,
                      title: const Text(
                        'ยินยอมส่งข้อความที่พิมพ์หรือพูดให้ Google Gemini',
                      ),
                      subtitle: const Text(
                        'จำเป็นสำหรับผู้ช่วยฝึกภาษา และยกเลิกได้ทุกเมื่อ',
                      ),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _providerConsent = value ?? false;
                              if (!_providerConsent) _summaryConsent = false;
                            }),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _summaryConsent,
                      title: const Text('แชร์สรุปผลเรียนแบบย่อกับ Gemini'),
                      subtitle: const Text(
                        'ส่งเฉพาะจำนวนคำตอบ ความแม่นยำ จำนวนคำที่ถึงกำหนด '
                        'และคำอ่อนสูงสุด 3 คำ ไม่ส่งอีเมล รหัสบัญชี หรือประวัติดิบ',
                      ),
                      onChanged: !_providerConsent || _saving
                          ? null
                          : (value) => setState(
                              () => _summaryConsent = value ?? false,
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey<String>('gemini-settings-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _notice!,
                          key: const ValueKey<String>('gemini-settings-notice'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey<String>('gemini-save-key'),
                      onPressed: _saving ? null : _validateAndSave,
                      child: Text(
                        _saving
                            ? 'กำลังตรวจสอบ...'
                            : _hasKey
                            ? 'ตรวจสอบและเปลี่ยนรหัส'
                            : 'ตรวจสอบและบันทึกรหัส',
                      ),
                    ),
                    if (_saving)
                      TextButton(
                        onPressed: () => _cancellation?.cancel(),
                        child: const Text('ยกเลิกการตรวจสอบ'),
                      ),
                    if (_hasKey) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _saving ? null : _saveConsents,
                        child: const Text('ใช้การยินยอมสำหรับรอบนี้'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const ValueKey<String>('gemini-remove-key'),
                        onPressed: _saving ? null : _removeKey,
                        child: const Text('ลบรหัสเชื่อมต่อ Gemini'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  String _failureText(GeminiFailureCode code) => switch (code) {
    GeminiFailureCode.invalidKey =>
      'รหัสเชื่อมต่อไม่ถูกต้อง ถูกบล็อก หรือใช้กับ Gemini ไม่ได้',
    GeminiFailureCode.quota => 'โควตาหรือเพดานใช้งานของโครงการเต็มแล้ว',
    GeminiFailureCode.offline => 'อุปกรณ์ออฟไลน์หรือเชื่อมต่อเครือข่ายไม่ได้',
    GeminiFailureCode.timeout => 'การตรวจสอบใช้เวลานานเกินกำหนด',
    GeminiFailureCode.providerUnavailable =>
      'ผู้ให้บริการ Gemini ไม่พร้อมใช้งานชั่วคราว',
    GeminiFailureCode.malformedResponse =>
      'Gemini ส่งข้อมูลตอบกลับที่อ่านไม่ได้',
    GeminiFailureCode.consentRequired => 'ต้องยืนยันการยินยอมก่อนบันทึกรหัส',
    GeminiFailureCode.cancelled => 'ยกเลิกการตรวจสอบแล้ว',
    GeminiFailureCode.secureStorage =>
      'ที่จัดเก็บปลอดภัยของอุปกรณ์ไม่พร้อมใช้งาน',
    GeminiFailureCode.missingKey => 'ยังไม่มีรหัสเชื่อมต่อ Gemini',
    GeminiFailureCode.blocked => 'คำขอถูกระบบความปลอดภัยของ Gemini ปฏิเสธ',
    GeminiFailureCode.validation => 'ข้อมูลที่กรอกไม่ถูกต้อง',
  };
}
