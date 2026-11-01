import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../../export/domain/export_contracts.dart';
import '../../progress/application/progress_use_cases.dart';
import '../application/controlled_study_archive_use_cases.dart';
import '../application/controlled_study_upload_use_cases.dart';
import '../domain/study_archive.dart';
import 'study_upload_actions.dart';

class StudyArchiveScreen extends StatefulWidget {
  const StudyArchiveScreen({
    super.key,
    this.archives,
    this.uploads,
    this.ownerChanges,
  });
  final ControlledStudyArchiveUseCases? archives;
  final ControlledStudyUploadUseCases? uploads;
  final Stream<String?>? ownerChanges;

  @override
  State<StudyArchiveScreen> createState() => _StudyArchiveScreenState();
}

class _StudyArchiveScreenState extends State<StudyArchiveScreen>
    with WidgetsBindingObserver {
  ControlledStudyArchiveUseCases? _archives;
  ControlledStudyUploadUseCases? _uploads;
  ProgressUseCases? _progress;
  Stream<String?>? _ownerSource;
  StreamSubscription<String?>? _owners;
  ExportCancellation? _cancellation;
  List<StudyArchivePreview> _cycles = const [];
  String? _owner;
  String? _status;
  int _generation = 0;
  int _selected = 0;
  bool _configured = false;
  bool _loading = false;
  bool _busy = false;
  bool _uploadBusy = false;
  bool _retired = false;
  AppDependencies? _dependencies;
  final _exportCycles = <String>{};
  final _uploadCycles = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(StudyArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_configured && !identical(_dependencies, dependencies)) {
      _retired = true;
      _generation++;
      _cancellation?.cancel();
      unawaited(_owners?.cancel());
      _archives = null;
      _uploads = null;
      _owner = null;
      _cycles = const [];
      _loading = false;
      _busy = false;
      _uploadBusy = false;
      _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดกลับไปเลือกรอบใหม่';
      return;
    }
    _dependencies = dependencies;
    if (_retired) return;
    final archives = widget.archives ?? dependencies?.studyArchives;
    final uploads = widget.uploads ?? dependencies?.studyUploads;
    final progress = dependencies?.progress;
    if (_configured &&
        identical(_archives, archives) &&
        identical(_uploads, uploads) &&
        identical(_progress, progress) &&
        identical(_ownerSource, widget.ownerChanges)) {
      return;
    }
    _configured = true;
    _generation++;
    _cancellation?.cancel();
    unawaited(_owners?.cancel());
    _archives = archives;
    _uploads = uploads;
    _progress = progress;
    _ownerSource = widget.ownerChanges;
    _owner = null;
    _cycles = const [];
    _busy = false;
    _uploadBusy = false;
    _exportCycles.clear();
    _uploadCycles.clear();
    _loading = archives != null || uploads != null;
    _owners = (widget.ownerChanges ?? progress?.watchActiveOwnerId())?.listen(
      _ownerChanged,
      onError: (Object _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
    if (_owners == null) _loading = false;
  }

  void _ownerChanged(String? owner) {
    if (!mounted || _retired) return;
    _generation++;
    _cancellation?.cancel();
    setState(() {
      _owner = owner;
      _cycles = const [];
      _selected = 0;
      _busy = false;
      _uploadBusy = false;
      _exportCycles.clear();
      _uploadCycles.clear();
      _loading = owner != null;
      _status = null;
    });
    if (owner != null) unawaited(_reload());
  }

  Future<void> _reload() async {
    final archives = _archives;
    final uploads = _uploads;
    final owner = _owner;
    if ((archives == null && uploads == null) || owner == null || _retired) {
      return;
    }
    final generation = ++_generation;
    bool current() =>
        mounted &&
        generation == _generation &&
        _owner == owner &&
        identical(_archives, archives) &&
        identical(_uploads, uploads);
    setState(() {
      _loading = true;
      _cycles = const [];
      _exportCycles.clear();
      _uploadCycles.clear();
      _uploadBusy = false;
      _status = null;
    });
    try {
      var failed = false;
      var exported = <StudyArchivePreview>[];
      var uploaded = <StudyArchivePreview>[];
      if (archives != null) {
        try {
          exported = await archives.listCycles(
            expectedOwnerId: owner,
            stillCurrent: current,
          );
        } on Object {
          failed = true;
        }
      }
      if (!current()) return;
      if (uploads != null) {
        try {
          uploaded = await uploads.listCycles(
            expectedOwnerId: owner,
            stillCurrent: current,
          );
        } on Object {
          failed = true;
        }
      }
      if (!current()) return;
      final cycles =
          {
              for (final value in [...exported, ...uploaded])
                value.target.studyCycleId: value,
            }.values.toList()
            ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
      setState(() {
        _cycles = cycles;
        _selected = 0;
        _exportCycles.addAll(
          exported.map((cycle) => cycle.target.studyCycleId),
        );
        _uploadCycles.addAll(
          uploaded.map((cycle) => cycle.target.studyCycleId),
        );
        if (cycles.isEmpty && failed) {
          _status = 'ยังส่งออกหรือส่งข้อมูลไม่ได้ โปรดตรวจสอบสิทธิ์ปัจจุบัน';
        }
      });
    } on Object {
      if (current()) {
        setState(
          () =>
              _status = 'ยังส่งออกไม่ได้ โปรดตรวจสอบสิทธิ์ปัจจุบันแล้วลองใหม่',
        );
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final archives = _archives;
    final owner = _owner;
    if (_busy ||
        _uploadBusy ||
        _retired ||
        archives == null ||
        owner == null ||
        _cycles.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final cancellation = _cancellation = ExportCancellation();
    final target = _cycles[_selected].target;
    bool current() =>
        mounted &&
        generation == _generation &&
        _owner == owner &&
        identical(_archives, archives);
    setState(() {
      _busy = true;
      _status = 'กำลังเตรียมไฟล์เฉพาะรอบที่เลือก';
    });
    try {
      final result = await archives.exportCycle(
        target: target,
        cancellation: cancellation,
        stillCurrent: current,
      );
      if (current()) {
        setState(() => _status = 'บันทึกไฟล์แล้ว ${result.bytesWritten} ไบต์');
      }
    } on ExportException catch (error) {
      if (current()) {
        setState(
          () => _status = error.code == ExportFailureCode.cancelled
              ? 'ยกเลิกการส่งออกแล้ว'
              : 'ยังส่งออกไม่ได้ โปรดตรวจสอบสิทธิ์ปัจจุบันแล้วลองใหม่',
        );
      }
    } on Object {
      if (current()) setState(() => _status = 'ส่งออกไม่สำเร็จ โปรดลองใหม่');
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _uploadBusy = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _generation++;
      _cancellation?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _cycles = const [];
          _loading = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancellation?.cancel();
    unawaited(_owners?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _state(String state) => switch (state) {
    'active' || 'started' || 'inProgress' => 'กำลังเก็บข้อมูล',
    'completed' => 'เสร็จสิ้น',
    'abandoned' => 'ยุติรอบแล้ว',
    _ => 'รอบข้อมูลที่ได้รับอนุญาต',
  };

  @override
  Widget build(BuildContext context) {
    final cycle = _cycles.isEmpty ? null : _cycles[_selected];
    final uploadService = _uploads;
    final generation = _generation;
    final owner = _owner;
    return Scaffold(
      appBar: AppBar(title: const Text('ส่งออกและส่งข้อมูล Study')),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'เลือกเฉพาะรอบที่ได้รับอนุญาต ไฟล์จะเก็บผลแบบสอบถามและการประเมินแยกกัน พร้อมระบุส่วนที่ยังไม่ครบ',
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังตรวจสอบรอบที่ส่งออกได้',
                ),
              ),
            if (!_loading && _cycles.isEmpty)
              const Text('ไม่มีรอบที่ส่งออกได้ในขณะนี้'),
            if (cycle != null) ...[
              DropdownButtonFormField<int>(
                key: ValueKey((_owner, _cycles)),
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'รอบที่ได้รับอนุญาต',
                ),
                items: [
                  for (var index = 0; index < _cycles.length; index++)
                    DropdownMenuItem(
                      value: index,
                      child: Text(
                        '${_cycles[index].startedAtUtc.toLocal().toString().split(' ').first} · ${_state(_cycles[index].state)}',
                      ),
                    ),
                ],
                onChanged: _busy || _uploadBusy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _selected = value);
                      },
              ),
              const SizedBox(height: 12),
              Text('คำตอบแบบสอบถาม ${cycle.motivationResponseCount} รายการ'),
              Text('การประเมินที่มี ${cycle.assessmentPhases.length} ช่วง'),
              if (cycle.missingPhases.isNotEmpty)
                Text(
                  'ข้อมูลยังไม่ครบ ${cycle.missingPhases.length} ส่วน ไฟล์จะระบุส่วนที่ขาด',
                ),
              const SizedBox(height: 16),
              if (_exportCycles.contains(cycle.target.studyCycleId))
                FilledButton.icon(
                  key: const ValueKey('study-archive-save'),
                  onPressed: _busy || _uploadBusy ? null : _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('เลือกที่เก็บและส่งออก'),
                ),
              if (uploadService != null &&
                  _uploadCycles.contains(cycle.target.studyCycleId))
                StudyUploadActions(
                  uploads: uploadService,
                  target: cycle.target,
                  stillCurrent: () =>
                      mounted &&
                      !_retired &&
                      _generation == generation &&
                      _owner == owner &&
                      identical(_uploads, uploadService),
                  onBusyChanged: (busy) {
                    if (mounted && _generation == generation) {
                      setState(() => _uploadBusy = busy);
                    }
                  },
                ),
            ],
            if (_busy)
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: const Text('ยกเลิก'),
              ),
            if (!_busy && !_uploadBusy && !_loading && _owner != null)
              OutlinedButton(
                onPressed: _reload,
                child: const Text('ตรวจสอบสิทธิ์และโหลดใหม่'),
              ),
            if (_status != null)
              Semantics(liveRegion: true, child: Text(_status!)),
          ],
        ),
      ),
    );
  }
}
