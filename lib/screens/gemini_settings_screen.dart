import 'package:flutter/material.dart';

import '../features/gemini/domain/gemini_contracts.dart';
import '../runtime/app_dependencies.dart';

class GeminiSettingsScreen extends StatefulWidget {
  const GeminiSettingsScreen({super.key, this.geminiTutor});

  final GeminiTutorController? geminiTutor;

  @override
  State<GeminiSettingsScreen> createState() => _GeminiSettingsScreenState();
}

class _GeminiSettingsScreenState extends State<GeminiSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  GeminiTutorController? _tutor;
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
    if (identical(resolved, _tutor)) return;
    _tutor = resolved;
    _load();
  }

  Future<void> _load() async {
    final tutor = _tutor;
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
      if (!mounted) return;
      setState(() {
        _hasKey = status.hasKey;
        _providerConsent = status.providerConsent;
        _summaryConsent = status.shareLearningSummary;
      });
    } on GeminiException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validateAndSave() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'กรุณากรอก Gemini API key');
      return;
    }
    final cancellation = GeminiCancellation();
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
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _hasKey = true;
        _notice = 'ตรวจสอบและเก็บ key ในที่จัดเก็บปลอดภัยแล้ว';
      });
    } on GeminiException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _saveConsents() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.updateConsents(
        providerConsent: _providerConsent,
        shareLearningSummary: _summaryConsent,
      );
      if (mounted) setState(() => _notice = 'บันทึกการยินยอมแล้ว');
    } on GeminiException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบ Gemini API key?'),
        content: const Text(
          'AI Tutor จะเรียก Gemini ไม่ได้จนกว่าจะเพิ่มและตรวจสอบ key ใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.removeKey();
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _hasKey = false;
        _providerConsent = false;
        _summaryConsent = false;
        _notice = 'ลบ key และปิดการส่งข้อมูลไป Gemini แล้ว';
      });
    } on GeminiException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini BYOK')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _hasKey
                        ? 'สถานะ: มี key ที่ตรวจสอบแล้ว'
                        : 'สถานะ: ยังไม่มี key',
                    key: const ValueKey<String>('gemini-key-status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Key ถูกเข้ารหัสขณะเก็บในเครื่องด้วย Android Keystore '
                    'และจะไม่ถูกบันทึกในฐานข้อมูลหรือ log แต่แอปบนมือถือไม่อาจ '
                    'รับประกันว่า key จะดึงออกจากหน่วยความจำไม่ได้ทุกกรณี '
                    'ควรใช้ key แยกสำหรับงานทดลองและตั้งเพดานงบใน Google AI Studio',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey<String>('gemini-key-input'),
                    controller: _keyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: _hasKey
                          ? 'Gemini API key ใหม่'
                          : 'Gemini API key',
                      helperText: _hasKey
                          ? 'กรอกเฉพาะเมื่อต้องการเปลี่ยน key'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _providerConsent,
                    title: const Text(
                      'ยินยอมส่งข้อความที่พิมพ์หรือพูดให้ Google Gemini',
                    ),
                    subtitle: const Text(
                      'จำเป็นสำหรับ AI Tutor และยกเลิกได้ทุกเมื่อ',
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
                        : (value) =>
                              setState(() => _summaryConsent = value ?? false),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const ValueKey<String>('gemini-settings-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _notice!,
                      key: const ValueKey<String>('gemini-settings-notice'),
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
                          ? 'ตรวจสอบและเปลี่ยน key'
                          : 'ตรวจสอบและบันทึก key',
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
                      child: const Text('บันทึกการยินยอม'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey<String>('gemini-remove-key'),
                      onPressed: _saving ? null : _removeKey,
                      child: const Text('ลบ Gemini API key'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  String _failureText(GeminiFailureCode code) => switch (code) {
    GeminiFailureCode.invalidKey =>
      'Key ไม่ถูกต้อง ถูกบล็อก หรือใช้กับ Gemini ไม่ได้',
    GeminiFailureCode.quota => 'โควตาหรือเพดานใช้งานของโครงการเต็มแล้ว',
    GeminiFailureCode.rateLimited => 'Gemini จำกัดอัตราการเรียก กรุณารอสักครู่',
    GeminiFailureCode.offline => 'อุปกรณ์ออฟไลน์หรือเชื่อมต่อเครือข่ายไม่ได้',
    GeminiFailureCode.timeout => 'การตรวจสอบใช้เวลานานเกินกำหนด',
    GeminiFailureCode.providerUnavailable =>
      'ผู้ให้บริการ Gemini ไม่พร้อมใช้งานชั่วคราว',
    GeminiFailureCode.malformedResponse =>
      'Gemini ส่งข้อมูลตอบกลับที่อ่านไม่ได้',
    GeminiFailureCode.consentRequired => 'ต้องยืนยันการยินยอมก่อนบันทึก key',
    GeminiFailureCode.cancelled => 'ยกเลิกการตรวจสอบแล้ว',
    GeminiFailureCode.secureStorage =>
      'ที่จัดเก็บปลอดภัยของอุปกรณ์ไม่พร้อมใช้งาน',
    GeminiFailureCode.missingKey => 'ยังไม่มี Gemini API key',
    GeminiFailureCode.blocked => 'คำขอถูกระบบความปลอดภัยของ Gemini ปฏิเสธ',
    GeminiFailureCode.validation => 'ข้อมูลที่กรอกไม่ถูกต้อง',
  };
}
