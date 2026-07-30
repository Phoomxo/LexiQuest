import 'package:flutter/material.dart';

import '../features/export/application/export_use_cases.dart';
import '../features/export/domain/export_contracts.dart';
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
      _cancellation = cancellation;
      _status = 'กำลังสร้างไฟล์จากข้อมูลในเครื่อง';
    });
    try {
      final result = await exports.export(
        format: _format,
        selection: ExportSelection(
          includeVocabulary: _vocabulary,
          includeAttempts: _attempts,
          includeReading: _reading,
        ),
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _status = 'บันทึกแล้ว ${result.bytesWritten} ไบต์\n${result.path}';
      });
    } on ExportException catch (error) {
      if (!mounted) return;
      setState(() => _status = _failureText(error.code));
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
    setState(() => _status = 'กำลังยกเลิก');
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ส่งออกข้อมูล')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'เลือกรูปแบบไฟล์',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(value: ExportFormat.csv, label: Text('CSV')),
              ButtonSegment(value: ExportFormat.pdf, label: Text('PDF')),
              ButtonSegment(value: ExportFormat.anki, label: Text('Anki')),
              ButtonSegment(
                value: ExportFormat.researchJson,
                label: Text('Research'),
              ),
            ],
            selected: {_format},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _format = selection.single),
          ),
          const SizedBox(height: 20),
          Text('เลือกข้อมูล', style: Theme.of(context).textTheme.titleMedium),
          CheckboxListTile(
            value: _vocabulary,
            onChanged: _busy
                ? null
                : (value) => setState(() => _vocabulary = value ?? false),
            title: const Text('คลังคำศัพท์'),
            subtitle: const Text('คำศัพท์ หมวดหมู่ ความหมาย และแหล่งที่มา'),
          ),
          CheckboxListTile(
            value: _attempts,
            onChanged: _busy
                ? null
                : (value) => setState(() => _attempts = value ?? false),
            title: const Text('ประวัติคำตอบ'),
            subtitle: const Text('ผลตอบ เวลาตอบ โหมด และ provenance'),
          ),
          CheckboxListTile(
            value: _reading,
            onChanged: _busy
                ? null
                : (value) => setState(() => _reading = value ?? false),
            title: const Text('ประวัติการอ่าน'),
            subtitle: const Text('ตำแหน่ง เอกสาร revision และสถานะอ่านจบ'),
          ),
          const SizedBox(height: 12),
          const Text(
            'ไฟล์ระบุ sample size, UTC, schema version, algorithm version '
            'และรายการข้อมูลที่ไม่รวม โดยไม่ส่งออก API key หรือ token',
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: _busy
                ? OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('ยกเลิก'),
                  )
                : FilledButton.icon(
                    onPressed: _export,
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
    );
  }

  String _failureText(ExportFailureCode code) => switch (code) {
    ExportFailureCode.noSelection => 'กรุณาเลือกข้อมูลอย่างน้อยหนึ่งประเภท',
    ExportFailureCode.noData => 'ไม่มีข้อมูลจริงสำหรับรูปแบบที่เลือก (N=0)',
    ExportFailureCode.consentRequired =>
      'ต้องยินยอมเข้าร่วมการทดลองก่อนส่งออกชุดข้อมูลวิจัย',
    ExportFailureCode.cancelled => 'ยกเลิกการส่งออกแล้ว',
    ExportFailureCode.permissionDenied => 'ไม่มีสิทธิ์เขียนไฟล์ไปยังตำแหน่งนี้',
    ExportFailureCode.insufficientSpace => 'พื้นที่จัดเก็บไม่เพียงพอ',
    ExportFailureCode.writeFailed =>
      'เขียนไฟล์ไม่สำเร็จและล้างไฟล์ชั่วคราวแล้ว',
    ExportFailureCode.unavailable => 'ระบบบันทึกไฟล์ไม่พร้อมใช้งาน',
  };
}
