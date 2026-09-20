import 'package:flutter/material.dart';

import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import '../runtime/app_dependencies.dart';

class AiTutorSettingsScreen extends StatefulWidget {
  const AiTutorSettingsScreen({super.key, this.aiTutor});

  final AiTutorController? aiTutor;

  @override
  State<AiTutorSettingsScreen> createState() => _AiTutorSettingsScreenState();
}

class _AiTutorSettingsScreenState extends State<AiTutorSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  AiTutorController? _tutor;
  AiCancellation? _cancellation;
  AiProviderId _providerId = AiProviderId.gemini;
  AiProviderId _savedProviderId = AiProviderId.gemini;
  String _savedBaseUrl = '';
  List<AiModel> _models = const [];
  String? _model;
  bool _loading = true;
  bool _settingsKnown = false;
  bool _usageKnown = false;
  bool _saving = false;
  bool _hasKey = false;
  bool _providerConsent = false;
  bool _summaryConsent = false;
  bool _savedProviderConsent = false;
  bool _savedSummaryConsent = false;
  bool _draftChanged = false;
  bool _allowLeave = false;

  bool get _dirty =>
      _draftChanged ||
      _providerConsent != _savedProviderConsent ||
      _summaryConsent != _savedSummaryConsent;

  bool _canReuseStoredKey() {
    if (_providerId == _savedProviderId &&
        (_providerId != AiProviderId.customOpenAi ||
            _baseUrlController.text.trim() == _savedBaseUrl)) {
      return true;
    }
    setState(() {
      _notice = null;
      _error =
          'คุณเปลี่ยนผู้ให้บริการหรือปลายทาง กรุณากรอกรหัสเชื่อมต่อสำหรับปลายทางนี้';
    });
    return false;
  }

  void _edited() => setState(() {
    _draftChanged = true;
    _notice = null;
  });

  Future<void> _confirmLeave() async {
    final generation = _tutorGeneration;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกโดยไม่บันทึก?'),
        content: Text(
          _settingsKnown
              ? 'ค่าที่แก้ไขยังไม่ถูกบันทึก การตั้งค่าและความยินยอมที่แสดงว่าบันทึกไว้ยังมีผล'
              : 'ยังยืนยันผลการบันทึกและความยินยอมปัจจุบันไม่ได้ การออกจากหน้านี้ไม่ได้ยกเลิกการบันทึกที่อาจเกิดขึ้นแล้ว',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('กลับไปแก้ไข'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกโดยไม่บันทึก'),
          ),
        ],
      ),
    );
    if (leave == true && _isCurrent(generation)) {
      setState(() => _allowLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrent(generation)) Navigator.pop(context);
      });
    }
  }

  String? _error;
  String? _notice;
  List<AiUsageSummary> _usageSummaries = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindTutor();
  }

  @override
  void didUpdateWidget(covariant AiTutorSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindTutor();
  }

  int _tutorGeneration = 0;
  bool _tutorResolved = false;

  bool _isCurrent(int generation) => mounted && generation == _tutorGeneration;

  void _bindTutor() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final resolvedTutor = widget.aiTutor ?? dependencies?.aiTutor;
    if (_tutorResolved && identical(resolvedTutor, _tutor)) return;
    _tutorResolved = true;
    _tutorGeneration++;
    _cancellation?.cancel();
    _cancellation = null;
    _tutor = resolvedTutor;
    _settingsKnown = false;
    _usageKnown = false;
    _hasKey = false;
    _providerConsent = _savedProviderConsent = false;
    _summaryConsent = _savedSummaryConsent = false;
    _providerId = _savedProviderId = AiProviderId.gemini;
    _savedBaseUrl = '';
    _models = const [];
    _model = null;
    _usageSummaries = const [];
    _saving = false;
    _draftChanged = false;
    _allowLeave = false;
    _notice = null;
    _keyController.clear();
    _baseUrlController.clear();
    _load();
  }

  Future<void> _load() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null) {
      setState(() {
        _loading = false;
        _error = 'อารียังไม่พร้อมใช้งานในรุ่นนี้';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await tutor.loadSettings();
      if (!_isCurrent(generation)) return;
      setState(() {
        _settingsKnown = true;
        _hasKey = status.hasKey;
        _providerConsent = status.providerConsent;
        _summaryConsent = status.shareLearningSummary;
        _savedProviderConsent = status.providerConsent;
        _savedSummaryConsent = status.shareLearningSummary;
        _draftChanged = false;
        _providerId = status.providerId;
        _savedProviderId = status.providerId;
        _savedBaseUrl = status.customBaseUrl ?? '';
        _model = status.model;
        _models = status.model == null
            ? const []
            : [AiModel(id: status.model!)];
        _baseUrlController.text = status.customBaseUrl ?? '';
      });
      final usageSummaries = await tutor.loadUsage();
      if (_isCurrent(generation)) {
        setState(() {
          _usageSummaries = usageSummaries;
          _usageKnown = true;
        });
      }
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _loadModels() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    if (!_providerConsent) {
      setState(
        () => _error = 'กรุณาอนุญาตการส่งข้อมูลก่อนเชื่อมต่อผู้ให้บริการ',
      );
      return;
    }
    final key = _keyController.text.trim();
    // When an active key is already stored and no new key is typed, use the
    // stored-key path so the participant never needs to re-enter a secret.
    if (key.isEmpty && _hasKey) {
      if (!_canReuseStoredKey()) return;
      return _loadModelsFromStoredKey();
    }
    if (key.isEmpty) {
      setState(
        () => _error = 'กรุณากรอกรหัสเชื่อมต่อจากบัญชีผู้ให้บริการของคุณ',
      );
      return;
    }
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final models = await tutor.listModels(
        providerId: _providerId,
        key: key,
        customBaseUrl: _providerId == AiProviderId.customOpenAi
            ? _baseUrlController.text.trim()
            : null,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation)) return;
      if (models.isEmpty && _providerId != AiProviderId.customOpenAi) {
        setState(
          () =>
              _error = 'ไม่พบรุ่น AI ที่ใช้ได้ กรุณาตรวจบัญชีหรือผู้ให้บริการ',
        );
        return;
      }
      setState(() {
        _models = models;
        // Discovery never chooses on the participant's behalf.
        _model = null;
        _notice = models.isEmpty
            ? 'กรอกรหัสรุ่น AI ที่ปลายทางของคุณรองรับ'
            : 'เลือกรุ่น AI แล้วกดบันทึกผู้ให้บริการ';
      });
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// Loads the model list using the credential already in secure storage.
  /// Called when the participant has an active key but has not typed a new one.
  Future<void> _loadModelsFromStoredKey() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final models = await tutor.listModelsForActiveCredential(
        cancellation: cancellation,
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _models = models;
        // Discovery never chooses on the participant's behalf.
        _model = null;
        _notice = models.isEmpty
            ? 'กรอกรหัสรุ่น AI ที่ปลายทางของคุณรองรับ'
            : 'เลือกรุ่น AI แล้วกดบันทึกผู้ให้บริการ';
      });
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _validateAndSave() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final key = _keyController.text.trim();
    final model = _model?.trim() ?? '';
    if (!_providerConsent) {
      setState(
        () => _error = 'กรุณาอนุญาตการส่งข้อมูลก่อนเชื่อมต่อผู้ให้บริการ',
      );
      return;
    }
    if (model.isEmpty) {
      setState(() => _error = 'กรุณาเลือกหรือกรอกรุ่น AI');
      return;
    }
    // If the participant has an active stored key and has not typed a new one,
    // use configureActiveModel so the key never travels back to the UI layer.
    if (key.isEmpty && _hasKey) {
      if (!_canReuseStoredKey()) return;
      return _configureActiveModel(model: model);
    }
    if (key.isEmpty) {
      setState(
        () => _error = 'กรุณากรอกรหัสเชื่อมต่อจากบัญชีผู้ให้บริการของคุณ',
      );
      return;
    }
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.configure(
        key: key,
        providerConsent: true,
        shareLearningSummary: _summaryConsent,
        providerId: _providerId,
        model: model,
        customBaseUrl: _providerId == AiProviderId.customOpenAi
            ? _baseUrlController.text.trim()
            : null,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation)) return;
      _keyController.clear();
      setState(() {
        _hasKey = true;
        _savedProviderId = _providerId;
        _savedBaseUrl = _baseUrlController.text.trim();
        _savedProviderConsent = _providerConsent;
        _savedSummaryConsent = _summaryConsent;
        _draftChanged = false;
        _notice = 'ตรวจสอบและบันทึกรหัสเชื่อมต่ออย่างปลอดภัยแล้ว';
      });
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// Saves only the model and summary-consent flag using the credential
  /// already in secure storage. Called when the participant has an active key
  /// and has not typed a replacement key.
  Future<void> _configureActiveModel({required String model}) async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.configureActiveModel(
        model: model,
        shareLearningSummary: _summaryConsent,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _savedSummaryConsent = _summaryConsent;
        _draftChanged = false;
        _notice = 'บันทึกรุ่น AI แล้ว';
      });
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() => _error = _failureText(error.code));
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _saveConsents({bool withdraw = false}) async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final providerConsent = withdraw ? false : _providerConsent;
    final summaryConsent = providerConsent && _summaryConsent;
    setState(() {
      _saving = true;
      _error = null;
      _notice = 'กำลังบันทึกความยินยอม…';
    });
    try {
      await tutor.updateConsents(
        providerConsent: providerConsent,
        shareLearningSummary: summaryConsent,
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _savedProviderConsent = _providerConsent = providerConsent;
        _savedSummaryConsent = _summaryConsent = summaryConsent;
        _notice = providerConsent
            ? 'บันทึกความยินยอมแล้ว'
            : 'หยุดอนุญาตการส่งข้อความและสรุปการเรียนแล้ว';
      });
    } on AiTutorException catch (error) {
      if (!_isCurrent(generation)) return;
      if (_isCurrent(generation)) {
        setState(() {
          _settingsKnown = false;
          _notice = 'กำลังตรวจสอบผลการบันทึกความยินยอม…';
          _error = null;
        });
      }
      try {
        final status = await tutor.loadSettings();
        if (!_isCurrent(generation)) return;
        setState(() {
          _settingsKnown = true;
          _hasKey = status.hasKey;
          _savedProviderId = status.providerId;
          _savedBaseUrl = status.customBaseUrl ?? '';
          _savedProviderConsent = status.providerConsent;
          _savedSummaryConsent = status.shareLearningSummary;
          _notice = status.providerConsent
              ? 'ตรวจสอบแล้ว: อนุญาตส่งข้อความตามสถานะที่บันทึก'
              : 'ตรวจสอบแล้ว: ไม่อนุญาตส่งข้อความและสรุปการเรียน';
        });
      } on AiTutorException {
        if (_isCurrent(generation)) {
          setState(() {
            _notice = 'ยังยืนยันผลการบันทึกและความยินยอมปัจจุบันไม่ได้';
            _error = _failureText(error.code);
          });
        }
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรหัสเชื่อมต่อ AI?'),
        content: const Text(
          'อารีจะหยุดเชื่อมต่อผู้ให้บริการจนกว่าจะตรวจสอบรหัสเชื่อมต่อ '
          'และรุ่น AI ใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบรหัสเชื่อมต่อ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(generation)) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = 'กำลังลบรหัสเชื่อมต่อ…';
    });
    try {
      await tutor.removeKey();
      if (!_isCurrent(generation)) return;
      _keyController.clear();
      setState(() {
        _hasKey = false;
        _providerConsent = false;
        _summaryConsent = false;
        _savedProviderConsent = false;
        _savedSummaryConsent = false;
        _draftChanged = false;
        _models = const [];
        _model = null;
        _notice = 'ลบรหัสเชื่อมต่อและความยินยอมแล้ว';
      });
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() {
          _notice = null;
          _error = _failureText(error.code);
        });
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
    }
  }

  Future<void> _clearUsage() async {
    final tutor = _tutor;
    final generation = _tutorGeneration;
    if (tutor == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ล้างสถิติการใช้ AI ในเครื่อง?'),
        content: const Text(
          'ลบสถิติผู้ให้บริการ รุ่น AI หน่วยข้อความ เวลารอ และผลคำขอในเครื่องถาวร '
          'ไม่ลบรหัสเชื่อมต่อหรือข้อความสนทนา '
          'และไม่ลบประวัติหรือยอดเรียกเก็บของผู้ให้บริการ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ล้างสถิติในเครื่อง'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(generation)) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = 'กำลังล้างสถิติในเครื่อง…';
    });
    try {
      await tutor.clearUsage();
      if (!_isCurrent(generation)) return;
      final summaries = await tutor.loadUsage();
      if (_isCurrent(generation)) {
        setState(() {
          _usageSummaries = summaries;
          _usageKnown = true;
          _notice = 'ล้างสถิติการใช้ AI ในเครื่องแล้ว';
        });
      }
    } on AiTutorException catch (error) {
      if (_isCurrent(generation)) {
        setState(() {
          _notice = null;
          _error = _failureText(error.code);
        });
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = AiProviderConfig.forId(_providerId);
    final destination = _providerId == AiProviderId.customOpenAi
        ? (_baseUrlController.text.trim().isEmpty
              ? 'ยังไม่ได้ระบุปลายทาง'
              : _baseUrlController.text.trim())
        : config.baseUri.toString();
    return PopScope(
      canPop: _allowLeave || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ตั้งค่าการเชื่อมต่อ AI')),
        bottomNavigationBar: _error == null && _notice == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null)
                          Text(
                            _error!,
                            key: const ValueKey('ai-settings-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_notice != null)
                          Text(
                            _notice!,
                            key: const ValueKey('ai-settings-notice'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      !_settingsKnown
                          ? 'ยังตรวจสอบการตั้งค่าและความยินยอมไม่ได้'
                          : _hasKey
                          ? 'มีรหัสเชื่อมต่อที่บันทึกไว้'
                          : 'ยังไม่มีรหัสเชื่อมต่อ',
                      key: const ValueKey('ai-key-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_settingsKnown && _hasKey)
                      Text(
                        'ผู้ให้บริการที่บันทึกไว้: ${AiProviderConfig.forId(_savedProviderId).displayName}',
                      ),
                    if (_settingsKnown)
                      Text(
                        _savedProviderConsent
                            ? 'ความยินยอมที่บันทึก: อนุญาตส่งข้อความ'
                            : 'ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ',
                      ),
                    if (_settingsKnown)
                      Text(
                        _savedSummaryConsent
                            ? 'สรุปการเรียนที่บันทึก: อนุญาต'
                            : 'สรุปการเรียนที่บันทึก: ไม่อนุญาต',
                      ),
                    if (_dirty)
                      Text(
                        _settingsKnown
                            ? 'มีค่าที่แก้ไขแต่ยังไม่บันทึก ความยินยอมที่แสดงว่าบันทึกไว้ยังมีผล'
                            : 'ค่าที่แก้ไขยังไม่ยืนยันการบันทึก',
                      ),
                    if (_savedProviderConsent)
                      OutlinedButton.icon(
                        key: const ValueKey('ai-withdraw-consent'),
                        onPressed: _saving
                            ? null
                            : () => _saveConsents(withdraw: true),
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: const Text('หยุดอนุญาตการส่งข้อมูลตอนนี้'),
                      ),
                    const SizedBox(height: 16),
                    const Text('1. เตรียมบัญชีและรหัสเชื่อมต่อของคุณ'),
                    const Text(
                      'คุณต้องมีบัญชีผู้ให้บริการ AI และสร้างรหัสเชื่อมต่อ (API key) จากบัญชีนั้น ค่าใช้บริการคิดตามเงื่อนไขของผู้ให้บริการ แอปไม่ทราบยอดเรียกเก็บจริง',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AiProviderId>(
                      key: const ValueKey('ai-provider-select'),
                      initialValue: _providerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'ผู้ให้บริการ AI',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final provider in AiProviderConfig.all)
                          DropdownMenuItem(
                            value: provider.id,
                            child: Text(
                              provider.id == AiProviderId.customOpenAi
                                  ? 'กำหนดปลายทางเอง (ขั้นสูง)'
                                  : '${provider.displayName} (ทดลอง)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _providerId = value;
                                _models = const [];
                                _model = null;
                                _error = null;
                                _notice = null;
                                _draftChanged = true;
                              });
                            },
                    ),
                    if (_providerId == AiProviderId.customOpenAi)
                      ExpansionTile(
                        title: const Text('ขั้นสูง: ปลายทางที่กำหนดเอง'),
                        initiallyExpanded: true,
                        children: [
                          TextField(
                            key: const ValueKey('ai-custom-base-url'),
                            controller: _baseUrlController,
                            enabled: !_saving,
                            onChanged: (_) => _edited(),
                            decoration: const InputDecoration(
                              labelText: 'ที่อยู่ปลายทาง HTTPS',
                              helperText:
                                  'รหัสเชื่อมต่อและข้อความจะส่งไปยังที่อยู่นี้',
                              helperMaxLines: 3,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const Text(
                            'รองรับบริการที่ใช้รูปแบบ OpenAI-compatible เท่านั้น',
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('ai-key-input'),
                      controller: _keyController,
                      enabled: !_saving,
                      onChanged: (_) => _edited(),
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'รหัสเชื่อมต่อ (API key)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('2. ตรวจปลายทางและอนุญาตการเชื่อมต่อ'),
                    Text('ปลายทางที่จะเชื่อมต่อ: $destination'),
                    const Text(
                      'การโหลดรุ่นส่งรหัสเชื่อมต่อไปตรวจสอบ การบันทึกส่งคำขอทดสอบสั้น ๆ และอาจใช้โควตาหรือมีค่าใช้จ่าย การตั้งค่าเดิมยังอยู่หากตรวจสอบไม่ผ่าน',
                    ),
                    CheckboxListTile(
                      key: const ValueKey('ai-provider-consent'),
                      contentPadding: EdgeInsets.zero,
                      value: _providerConsent,
                      title: const Text(
                        'อนุญาตส่งข้อความฝึกสนทนาไปยังผู้ให้บริการ',
                      ),
                      subtitle: const Text(
                        'ค่าที่เลือกจะมีผลกับการสนทนาเมื่อบันทึกความยินยอมหรือบันทึกผู้ให้บริการแล้ว',
                      ),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _providerConsent = value ?? false;
                              if (!_providerConsent) _summaryConsent = false;
                              _notice = null;
                            }),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _summaryConsent,
                      title: const Text(
                        'อนุญาตส่งสรุปการเรียนเพิ่มเติม (ไม่บังคับ)',
                      ),
                      subtitle: const Text(
                        'ส่งเฉพาะความแม่นยำโดยรวมและจุดที่ควรฝึกไม่เกิน 3 ข้อ ไม่ส่งรหัสบัญชีหรือประวัติคำตอบรายข้อ',
                      ),
                      onChanged: !_providerConsent || _saving
                          ? null
                          : (value) => setState(() {
                              _summaryConsent = value ?? false;
                              _notice = null;
                            }),
                    ),
                    OutlinedButton(
                      key: const ValueKey('ai-load-models'),
                      onPressed: _saving ? null : _loadModels,
                      child: const Text('ตรวจรหัสและโหลดรุ่น AI'),
                    ),
                    const SizedBox(height: 16),
                    const Text('3. เลือกรุ่น AI แล้วบันทึก'),
                    if (_providerId == AiProviderId.customOpenAi &&
                        _models.isEmpty)
                      TextFormField(
                        key: const ValueKey('ai-custom-model'),
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'รหัสรุ่น AI',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _model = value.trim();
                          _edited();
                        },
                      )
                    else if (_models.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: const ValueKey('ai-model-select'),
                        initialValue: _model,
                        isExpanded: true,
                        hint: const Text('เลือกรุ่น AI'),
                        decoration: const InputDecoration(
                          labelText: 'รุ่น AI',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final model in _models)
                            DropdownMenuItem(
                              value: model.id,
                              child: Text(
                                model.displayName ?? model.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                _model = value;
                                _draftChanged = true;
                                _notice = null;
                              }),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('ai-save-key'),
                      onPressed: _saving ? null : _validateAndSave,
                      child: const Text('บันทึกผู้ให้บริการและรุ่น AI'),
                    ),
                    if (_saving) ...[
                      const LinearProgressIndicator(),
                      if (_cancellation != null)
                        TextButton(
                          onPressed: () => _cancellation?.cancel(),
                          child: const Text('ยกเลิกคำขอ'),
                        ),
                    ],
                    if (_hasKey) ...[
                      const Text(
                        'การบันทึกเฉพาะความยินยอมใช้กับผู้ให้บริการที่บันทึกไว้ โดยไม่เรียกตรวจรหัสหรือทดสอบรุ่น AI',
                      ),
                      OutlinedButton(
                        onPressed: _saving ? null : () => _saveConsents(),
                        child: const Text('บันทึกเฉพาะความยินยอม'),
                      ),
                      TextButton(
                        key: const ValueKey('ai-remove-key'),
                        onPressed: _saving ? null : _removeKey,
                        child: const Text('ลบรหัสเชื่อมต่อ AI'),
                      ),
                    ],
                    ExpansionTile(
                      title: const Text('รายละเอียดการเชื่อมต่อและการเก็บรหัส'),
                      children: const [
                        Text(
                          'รหัสเชื่อมต่อเก็บในพื้นที่ปลอดภัยของเครื่อง คำขอส่งตรงไปยังผู้ให้บริการที่เลือก Gemini อาจลองใหม่รวมไม่เกิน 3 ครั้งเมื่อขัดข้องชั่วคราว และจะไม่เปลี่ยนไปใช้ผู้ให้บริการอื่น',
                        ),
                      ],
                    ),
                    if (_tutor != null) ...[
                      const Divider(height: 32),
                      Text(
                        'สถิติการใช้ AI ในเครื่อง (90 วัน)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'เป็นสถิติที่แอปบันทึก ไม่ใช่ใบเรียกเก็บเงิน หากไม่ทราบค่าใช้จ่าย ไม่ได้หมายความว่าใช้ฟรี',
                      ),
                      if (!_usageKnown)
                        const Text('ยังโหลดสถิติการใช้ AI ไม่สำเร็จ')
                      else if (_usageSummaries.isEmpty)
                        const Text('ยังไม่มีสถิติการใช้ AI ในเครื่อง')
                      else
                        for (final summary in _usageSummaries)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${AiProviderConfig.forId(summary.providerId).displayName} / ${summary.model}',
                            ),
                            subtitle: Text(
                              '${summary.requestCount} คำขอ · ${_usageTokenText(summary)} · ค่าใช้จ่ายที่ผู้ให้บริการรายงาน: ${summary.providerReportedCostMicrosUsd == null ? 'ไม่ทราบ' : '${(summary.providerReportedCostMicrosUsd! / 1000000).toStringAsFixed(6)} USD'}',
                            ),
                          ),
                      TextButton(
                        key: const ValueKey('ai-clear-usage'),
                        onPressed: _saving ? null : _clearUsage,
                        child: const Text('ล้างเฉพาะสถิติการใช้ AI ในเครื่อง'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  String _usageTokenText(AiUsageSummary summary) {
    if (summary.totalTokens != null) {
      return '${summary.totalTokens} หน่วยข้อความ';
    }
    if (summary.tokenReportedRequestCount == 0) {
      return 'ไม่ทราบจำนวนหน่วยข้อความ';
    }
    return 'รายงานบางส่วน: ${summary.knownTokens} หน่วยข้อความ '
        '(${summary.tokenReportedRequestCount} จาก ${summary.requestCount} คำขอ)';
  }

  String _failureText(AiFailureCode code) => switch (code) {
    AiFailureCode.invalidKey =>
      'รหัสเชื่อมต่อไม่ถูกต้อง กรุณาตรวจจากบัญชีผู้ให้บริการ',
    AiFailureCode.requestRejected =>
      'ผู้ให้บริการไม่ยอมรับรุ่น AI หรือคำขอนี้ ลองเลือกรุ่นอื่น '
          'หรือตรวจข้อจำกัดบัญชีผู้ให้บริการ การตั้งค่าเดิม '
          'ยังมีผล',
    AiFailureCode.quota => 'โควตาหมด กรุณาตรวจบัญชีผู้ให้บริการ',
    AiFailureCode.rateLimited => 'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
    AiFailureCode.offline => 'ไม่มีอินเทอร์เน็ต กรุณาเชื่อมต่อแล้วลองใหม่',
    AiFailureCode.timeout => 'ผู้ให้บริการตอบไม่ทันเวลา กรุณาลองใหม่',
    AiFailureCode.providerUnavailable =>
      'ผู้ให้บริการไม่พร้อมชั่วคราว กรุณาลองภายหลัง',
    AiFailureCode.providerDisabled =>
      'ผู้ให้บริการถูกปิดใช้งาน กรุณาเลือกผู้ให้บริการอื่น',
    AiFailureCode.circuitOpen =>
      'พักการเชื่อมต่อหลังเกิดข้อผิดพลาดหลายครั้ง กรุณาลองภายหลัง',
    AiFailureCode.localPersistence =>
      'บันทึกสถิติ AI ในเครื่องไม่ได้ชั่วคราว กรุณาลองภายหลัง',
    AiFailureCode.malformedResponse =>
      'อ่านผลจากผู้ให้บริการไม่ได้ กรุณาลองใหม่',
    AiFailureCode.consentRequired =>
      'กรุณาอนุญาตการส่งข้อมูลก่อนเชื่อมต่อผู้ให้บริการ',
    AiFailureCode.cancelled => 'ยกเลิกคำขอแล้ว',
    AiFailureCode.secureStorage =>
      'เข้าถึงที่เก็บรหัสอย่างปลอดภัยไม่ได้ กรุณาลองภายหลัง',
    AiFailureCode.missingKey =>
      'กรุณากรอกรหัสเชื่อมต่อจากบัญชีผู้ให้บริการของคุณ',
    AiFailureCode.missingModel => 'กรุณาเลือกหรือกรอกรุ่น AI',
    AiFailureCode.blocked => 'ผู้ให้บริการปฏิเสธคำขอนี้ กรุณาตรวจการตั้งค่า',
    AiFailureCode.validation => 'ข้อมูลที่กรอกไม่ถูกต้อง กรุณาตรวจอีกครั้ง',
    AiFailureCode.unsafeEndpoint =>
      'ใช้ปลายทาง HTTPS สาธารณะ ไม่รองรับที่อยู่ในเครื่องหรือเครือข่ายส่วนตัว',
  };
}
