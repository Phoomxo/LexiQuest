import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/export/application/export_use_cases.dart';
import '../features/export/domain/export_contracts.dart';
import '../features/identity/domain/owner_lifecycle_manifest.dart';
import '../runtime/app_dependencies.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key, this.exports});

  final ExportUseCases? exports;

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  ExportUseCases? _exports;
  ExportFormat _format = ExportFormat.csv;
  bool _vocabulary = true;
  bool _attempts = true;
  bool _reading = true;
  bool _busy = false;
  ExportCancellation? _cancellation;
  String? _status;
  String _assistanceStatus = 'idle';
  String? _failureCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _exports ??=
        widget.exports ?? AppDependenciesScope.maybeOf(context)?.exports;
  }

  Future<void> _export() async {
    final exports = _exports;
    if (exports == null || _busy) return;
    final cancellation = ExportCancellation();
    setState(() {
      _busy = true;
      _assistanceStatus = 'running';
      _failureCode = null;
      _cancellation = cancellation;
      _status = 'กำลังสร้างไฟล์จากข้อมูลในเครื่อง';
    });
    try {
      final result = await exports.export(
        format: _format,
        selection: ExportSelection(
          includeVocabulary: _format == ExportFormat.anki || _vocabulary,
          includeAttempts: _format != ExportFormat.anki && _attempts,
          includeReading: _format != ExportFormat.anki && _reading,
        ),
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _assistanceStatus = 'saved';
        _status = 'บันทึกแล้ว ${result.bytesWritten} ไบต์\n${result.path}';
      });
    } on ExportException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _failureText(error.code);
        _assistanceStatus = 'failed';
        _failureCode = error.code.name;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellation = null;
        });
      }
    }
  }

  void _cancel() {
    _cancellation?.cancel();
    setState(() {
      _status = 'กำลังยกเลิก';
      _assistanceStatus = 'cancelling';
    });
  }

  void _changeSelection(VoidCallback change) {
    setState(() {
      change();
      _status = null;
      _assistanceStatus = 'idle';
      _failureCode = null;
    });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuActionBinding(
      id: 'export/guidance',
      label: 'Export format and operation status',
      onInvoke: null,
      readValue: jsonEncode({
        'format': _format.name,
        'status': _assistanceStatus,
        if (_failureCode != null) 'failureCode': _failureCode,
        'researchConsentRequired': _format == ExportFormat.researchJson,
        'scope': _format == ExportFormat.anki
            ? 'vocabulary-only'
            : _format == ExportFormat.ownerArchiveJson
            ? 'owner-manifest-not-restore'
            : 'selected-data',
        if (_format != ExportFormat.anki &&
            _format != ExportFormat.ownerArchiveJson)
          'selection': {
            'vocabulary': _vocabulary,
            'attempts': _attempts,
            'reading': _reading,
          },
        'purpose': _formatPurpose(_format),
        'fileAccess': 'native-controls-only-no-path-or-file-content-shared',
      }),
      child: Scaffold(
        appBar: AppBar(title: const Text('ส่งออกข้อมูล')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'เลือกรูปแบบไฟล์',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            RadioGroup<ExportFormat>(
              groupValue: _format,
              onChanged: (value) {
                if (!_busy && value != null) {
                  setState(() {
                    _format = value;
                    _status = null;
                    _assistanceStatus = 'idle';
                    _failureCode = null;
                  });
                }
              },
              child: Column(
                children: [
                  for (final format in ExportFormat.values)
                    RadioListTile<ExportFormat>(
                      key: ValueKey(format),
                      value: format,
                      enabled: !_busy,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_formatLabel(format)),
                      subtitle: Text(_formatPurpose(format)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_format != ExportFormat.ownerArchiveJson &&
                _format != ExportFormat.anki) ...[
              Text(
                'เลือกข้อมูล',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CheckboxListTile(
                value: _vocabulary,
                onChanged: _busy
                    ? null
                    : (value) =>
                          _changeSelection(() => _vocabulary = value ?? false),
                title: const Text('คลังคำศัพท์'),
                subtitle: const Text('คำศัพท์ หมวดหมู่ ความหมาย และแหล่งที่มา'),
              ),
              CheckboxListTile(
                value: _attempts,
                onChanged: _busy
                    ? null
                    : (value) =>
                          _changeSelection(() => _attempts = value ?? false),
                title: const Text('ประวัติคำตอบ'),
                subtitle: const Text('ผลตอบ เวลาตอบ และโหมดคำตอบ'),
              ),
              CheckboxListTile(
                value: _reading,
                onChanged: _busy
                    ? null
                    : (value) =>
                          _changeSelection(() => _reading = value ?? false),
                title: const Text('ประวัติการอ่าน'),
                subtitle: const Text(
                  'ตำแหน่งที่อ่าน รุ่นเอกสาร และสถานะอ่านจบ',
                ),
              ),
            ],
            if (_format == ExportFormat.ownerArchiveJson) ...[
              const Text(
                'สำเนาตามรายการข้อมูลของบัญชีปัจจุบันในเครื่อง ไม่ขึ้นกับตัวเลือกหมวดข้อมูล และไม่ต้องยินยอมเข้าร่วมวิจัย ไฟล์นี้ไม่ใช่ไฟล์สำหรับกู้คืนแอป',
              ),
              const Text(
                'ไม่รวมรหัสลับและโทเคนยืนยันตัวตน ข้อมูลระบุตัวผู้เข้าร่วมโดยตรง ข้อมูลดิบที่ไม่อยู่ในรายการอนุญาตและรายละเอียดจากผู้ให้บริการ ที่อยู่แหล่งข้อมูลและตำแหน่งไฟล์ในเครื่อง',
              ),
              ExpansionTile(
                title: const Text('ดูรายการข้อมูลและขอบเขตในสำเนา'),
                children: [
                  const Text(
                    'บางรายการเก็บเฉพาะผลรวม หรือปิดบังข้อมูลระบุตัวตน รายการด้านล่างอ้างอิงข้อกำหนดการส่งออกจริง ไม่ใช่จำนวนระเบียนที่มีข้อมูล',
                  ),
                  for (final entry in ownerLifecycleManifest)
                    ListTile(
                      title: Text(entry.alias),
                      subtitle: Text(
                        '${_dispositionLabel(entry.exportDisposition)}\nช่องข้อมูลที่อนุญาต: ${entry.allowedExportFields.join(', ')}',
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (_format != ExportFormat.ownerArchiveJson &&
                _format != ExportFormat.anki)
              const Text(
                'ส่งออกข้อมูลที่เลือกจากเครื่อง พร้อมข้อมูลประกอบตามรูปแบบไฟล์ เช่น จำนวนรายการและเวลามาตรฐาน UTC โดยไม่รวมรหัสเชื่อมต่อหรือโทเคนเข้าสู่ระบบ',
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _busy
                  ? OutlinedButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('ยกเลิก'),
                    )
                  : FilledButton.icon(
                      onPressed: _exports == null ? null : _export,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('สร้างและบันทึกไฟล์'),
                    ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const ValueKey<String>('export-status'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatLabel(ExportFormat format) => switch (format) {
    ExportFormat.csv => 'ตารางข้อมูล (CSV)',
    ExportFormat.pdf => 'เอกสารสำหรับอ่าน (PDF)',
    ExportFormat.anki => 'บัตรคำสำหรับ Anki',
    ExportFormat.researchJson => 'ชุดข้อมูลวิจัย (JSON)',
    ExportFormat.ownerArchiveJson => 'สำเนาข้อมูลของฉัน',
  };

  String _formatPurpose(ExportFormat format) => switch (format) {
    ExportFormat.csv => 'เปิดและจัดการข้อมูลที่เลือกในแอปตารางคำนวณ',
    ExportFormat.pdf => 'อ่านหรือพิมพ์รายงานข้อมูลที่เลือก',
    ExportFormat.anki => 'นำเข้าเป็นบัตรคำใน Anki ใช้เฉพาะคำศัพท์และความหมาย',
    ExportFormat.researchJson =>
      'สำหรับวิเคราะห์งานวิจัย ต้องมีความยินยอมวิจัยตามรุ่นที่กำหนด แยกจากการส่งออกส่วนตัว',
    ExportFormat.ownerArchiveJson =>
      'เก็บข้อมูลตามรายการที่ระบบอนุญาต พร้อมปิดบังข้อมูลบางส่วน เป็นไฟล์ JSON',
  };

  String _dispositionLabel(OwnerLifecycleExportDisposition disposition) =>
      switch (disposition) {
        OwnerLifecycleExportDisposition.redactedIdentity =>
          'ปิดบังข้อมูลระบุตัวตน',
        OwnerLifecycleExportDisposition.allowlistedPersonal =>
          'เฉพาะข้อมูลส่วนตัวที่อนุญาต',
        OwnerLifecycleExportDisposition.aggregateOnly => 'เฉพาะข้อมูลสรุป',
        OwnerLifecycleExportDisposition.redactedOwnerMetadata =>
          'ข้อมูลประกอบบัญชีที่ปิดบังแล้ว',
        OwnerLifecycleExportDisposition.preservedGlobal =>
          'ข้อมูลส่วนกลางตามข้อกำหนด',
      };

  String _failureText(ExportFailureCode code) => switch (code) {
    ExportFailureCode.noSelection => 'กรุณาเลือกข้อมูลอย่างน้อยหนึ่งประเภท',
    ExportFailureCode.noData => 'ยังไม่มีข้อมูลสำหรับรูปแบบที่เลือก',
    ExportFailureCode.consentRequired =>
      'กรุณาให้ความยินยอมสำหรับการส่งออกข้อมูลวิจัยก่อน การยินยอมนี้ไม่ใช่การสมัครเข้าร่วมการทดลอง',
    ExportFailureCode.cancelled => 'ยกเลิกการส่งออกแล้ว',
    ExportFailureCode.permissionDenied => 'ไม่มีสิทธิ์เขียนไฟล์ไปยังตำแหน่งนี้',
    ExportFailureCode.insufficientSpace => 'พื้นที่จัดเก็บไม่เพียงพอ',
    ExportFailureCode.writeFailed =>
      'ยังยืนยันการบันทึกไฟล์ไม่ได้ กรุณาตรวจตำแหน่งที่เลือกก่อนลองอีกครั้ง',
    ExportFailureCode.cleanupFailed =>
      'ล้างไฟล์ส่งออกไม่สำเร็จ อาจมีไฟล์ค้างอยู่ กรุณาตรวจตำแหน่งที่เลือก',
    ExportFailureCode.unavailable => 'ระบบบันทึกไฟล์ไม่พร้อมใช้งาน',
  };
}
