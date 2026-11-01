import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../export/domain/export_contracts.dart';
import '../application/controlled_study_upload_use_cases.dart';
import '../domain/research_transport_contracts.dart';
import '../domain/study_archive.dart';

class StudyUploadActions extends StatefulWidget {
  const StudyUploadActions({
    super.key,
    required this.uploads,
    required this.target,
    required this.stillCurrent,
    required this.onBusyChanged,
  });
  final ControlledStudyUploadUseCases uploads;
  final StudyArchiveTarget target;
  final bool Function() stillCurrent;
  final ValueChanged<bool> onBusyChanged;

  @override
  State<StudyUploadActions> createState() => _StudyUploadActionsState();
}

class _StudyUploadActionsState extends State<StudyUploadActions>
    with WidgetsBindingObserver {
  StudyUploadIntent? _intent;
  ExportCancellation? _cancellation;
  AppDependencies? _dependencies;
  bool _bound = false;
  bool _retired = false;
  bool _busy = false;
  int _generation = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_bound && !identical(dependencies, _dependencies)) {
      _retired = true;
      _invalidate();
      _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดกลับไปเลือกรอบใหม่';
    }
    _bound = true;
    _dependencies = dependencies;
  }

  @override
  void didUpdateWidget(StudyUploadActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.uploads, widget.uploads) ||
        oldWidget.target.expectedOwnerId != widget.target.expectedOwnerId ||
        oldWidget.target.studyCycleId != widget.target.studyCycleId) {
      _invalidate();
    }
  }

  void _invalidate() {
    _generation++;
    _cancellation?.cancel();
    _intent = null;
    _busy = false;
    _status = null;
  }

  Future<void> _upload() async {
    if (_busy || _retired || !widget.stillCurrent()) return;
    final generation = ++_generation;
    final service = widget.uploads;
    final target = widget.target;
    final cancellation = _cancellation = ExportCancellation();
    bool current() =>
        mounted &&
        !_retired &&
        !cancellation.isCancelled &&
        generation == _generation &&
        identical(widget.uploads, service) &&
        widget.target.expectedOwnerId == target.expectedOwnerId &&
        widget.target.studyCycleId == target.studyCycleId &&
        widget.stillCurrent();
    setState(() {
      _busy = true;
      _status = 'กำลังตรวจสิทธิ์และเตรียมข้อมูลรอบที่เลือก';
    });
    widget.onBusyChanged(true);
    try {
      var intent = _intent;
      if (intent == null) {
        intent = await service.prepareCycle(
          target: target,
          cancellation: cancellation,
          stillCurrent: current,
        );
        if (!current()) return;
        _intent = intent;
      }
      await service.submit(
        intent,
        cancellation: cancellation,
        stillCurrent: current,
      );
      if (current()) {
        setState(() {
          _intent = null;
          _status = 'เซิร์ฟเวอร์ยืนยันรับข้อมูลรอบนี้แล้ว';
        });
      }
    } on ResearchTransportException catch (error) {
      if (current()) {
        setState(
          () => _status = switch (error.code) {
            ResearchTransportFailureCode.conflict =>
              'ข้อมูลหรือสิทธิ์เปลี่ยนแล้ว โปรดตรวจสอบก่อนเตรียมข้อมูลชุดใหม่',
            ResearchTransportFailureCode.ownerChanged ||
            ResearchTransportFailureCode.denied ||
            ResearchTransportFailureCode.accountRequired =>
              'ยังส่งไม่ได้ โปรดตรวจสิทธิ์ Study ปัจจุบันก่อน',
            _ => 'ยังยืนยันผลรับข้อมูลไม่ได้ ลองส่งข้อมูลชุดเดิมอีกครั้งได้',
          },
        );
      }
    } on ExportException catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _status = error.code == ExportFailureCode.cancelled
              ? 'ยกเลิกการรอผลแล้ว หากส่งไปแล้วให้ตรวจสอบผลก่อนส่งชุดใหม่'
              : 'ยังเตรียมหรือส่งข้อมูลไม่ได้ โปรดตรวจสิทธิ์ปัจจุบัน',
        );
      }
    } on Object {
      if (current()) {
        setState(
          () => _status = 'ยังยืนยันผลรับข้อมูลไม่ได้ โปรดตรวจสอบอีกครั้ง',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _cancellation = null;
          if (cancellation.isCancelled) {
            _status =
                'ยกเลิกการรอผลแล้ว หากส่งไปแล้วให้ตรวจสอบผลก่อนส่งชุดใหม่';
          }
        });
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _cancellation?.cancel();
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      const Text(
        'อัปโหลดเฉพาะข้อมูลรอบที่เลือกเมื่อมีสิทธิ์ปัจจุบันครบทั้งสองเครื่องมือ',
      ),
      OutlinedButton.icon(
        key: const ValueKey('study-archive-upload'),
        onPressed: _busy || _retired ? null : _upload,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(
          _intent == null
              ? 'อัปโหลดข้อมูลรอบนี้'
              : 'ลองส่งข้อมูลชุดเดิมอีกครั้ง',
        ),
      ),
      if (_busy)
        TextButton(
          onPressed: () => _cancellation?.cancel(),
          child: const Text('ยกเลิกการรอผลอัปโหลด'),
        ),
      if (_intent != null && !_busy && !_retired)
        TextButton(
          key: const ValueKey('study-upload-new-snapshot'),
          onPressed: () => setState(() {
            _intent = null;
            _status =
                'ผลส่งครั้งก่อนอาจได้รับแล้ว การส่งครั้งถัดไปจะเตรียมข้อมูลปัจจุบันชุดใหม่';
          }),
          child: const Text('เตรียมข้อมูลปัจจุบันชุดใหม่'),
        ),
      if (_busy)
        const LinearProgressIndicator(semanticsLabel: 'กำลังส่งข้อมูล Study'),
      if (_status != null) Semantics(liveRegion: true, child: Text(_status!)),
    ],
  );
}
