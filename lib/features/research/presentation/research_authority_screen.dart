import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../../consent/domain/research_consent.dart';
import '../application/research_authority_lifecycle.dart';
import '../application/local_research_participation_activation.dart';
import '../application/research_transport_consent_coordinator.dart';
import '../domain/research_authority_snapshot.dart';
import '../domain/research_transport_contracts.dart';

class ResearchAuthorityScreen extends StatefulWidget {
  const ResearchAuthorityScreen({
    super.key,
    required this.consent,
    required this.authority,
    this.notice,
    this.participationActivation,
    this.nowUtc,
  });
  final ResearchTransportConsentCoordinator consent;
  final ResearchAuthorityLifecycle authority;
  final SuppliedResearchConsentNotice? notice;
  final LocalResearchParticipationActivation? participationActivation;
  final DateTime Function()? nowUtc;

  @override
  State<ResearchAuthorityScreen> createState() =>
      _ResearchAuthorityScreenState();
}

class _ResearchAuthorityScreenState extends State<ResearchAuthorityScreen>
    with WidgetsBindingObserver {
  late final ResearchTransportConsentCoordinator _consent;
  late final ResearchAuthorityLifecycle _authority;
  ResearchEnrollmentContext? _enrollment;
  ResearchConsentStatus? _local;
  AppDependencies? _dependencies;
  bool _bound = false;
  bool _retired = false;
  bool _busy = false;
  bool _reviewed = false;
  String? _reviewedNoticeSha;
  bool? _wasVisible;
  int _generation = 0;
  String? _status;
  StreamSubscription<ResearchAuthorityBinding?>? _bindings;
  bool _observing = false;
  ResearchAuthorityBinding? _observedBinding;

  bool get _visible =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _consent = widget.consent;
    _authority = widget.authority;
    _observedBinding = _consent.currentBinding();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_bound && !identical(dependencies, _dependencies)) _retire();
    _bound = true;
    _dependencies = dependencies;
    if (!_observing) {
      _observing = true;
      _bindings = _consent.bindingChanges?.listen(
        (binding) {
          if (!mounted || _retired) return;
          if (binding == _observedBinding) return;
          _observedBinding = binding;
          setState(_invalidate);
          if (binding != null) unawaited(_load());
        },
        onError: (Object _) {
          if (mounted) setState(_invalidate);
        },
      );
    }
    final visible = _visible;
    if (_wasVisible != visible) {
      _wasVisible = visible;
      _invalidate();
      if (visible && !_retired) unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(ResearchAuthorityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.consent, oldWidget.consent) ||
        !identical(widget.authority, oldWidget.authority) ||
        !identical(
          widget.participationActivation,
          oldWidget.participationActivation,
        )) {
      _retire();
    } else if (widget.notice?.contentSha256 !=
        oldWidget.notice?.contentSha256) {
      _invalidate();
      unawaited(_load());
    }
  }

  void _invalidate() {
    _generation++;
    _consent.retirePending();
    _busy = false;
    _reviewed = false;
    _reviewedNoticeSha = null;
    _enrollment = null;
    _local = null;
    _status = null;
  }

  void _retire() {
    _retired = true;
    _invalidate();
    _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดกลับไปเปิดหน้าสิทธิ์ Study ใหม่';
  }

  bool _current(int generation, ResearchAuthorityBinding binding) =>
      !_retired &&
      _visible &&
      generation == _generation &&
      _consent.currentBinding() == binding;

  Future<void> _load() async {
    if (_retired || !_visible) return;
    final binding = _consent.currentBinding();
    if (binding == null) {
      setState(
        () => _status = 'เข้าสู่ระบบด้วยบัญชีที่ได้รับสิทธิ์ก่อนตรวจสอบ Study',
      );
      return;
    }
    final generation = ++_generation;
    bool current() => _current(generation, binding);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final local = await _consent.loadLocalStatus(stillCurrent: current);
      if (!current()) return;
      setState(() => _local = local);
      final enrollment = await _consent.loadEnrollment(stillCurrent: current);
      if (!current()) return;
      setState(() {
        _enrollment = enrollment;
        _reviewed = false;
      });
    } on ResearchTransportException catch (error) {
      if (current()) setState(() => _status = _failure(error.code));
    } on Object {
      if (current()) {
        setState(() => _status = 'ยังอ่านสิทธิ์ไม่ได้ โปรดลองตรวจสอบอีกครั้ง');
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _command(
    Future<bool> Function(bool Function()) action,
    String success,
  ) async {
    final binding = _consent.currentBinding();
    if (_busy || _retired || binding == null) return;
    final generation = ++_generation;
    bool current() => _current(generation, binding);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final acknowledged = await action(current);
      if (!current()) return;
      final local = await _consent.loadLocalStatus(stillCurrent: current);
      if (current()) {
        setState(() {
          _local = local;
          _reviewed = false;
          _status = acknowledged
              ? success
              : 'ยังยืนยันสิทธิ์ปัจจุบันไม่ได้ การเรียนทั่วไปยังใช้ได้';
        });
      }
    } on ResearchTransportException catch (error) {
      if (current()) {
        ResearchConsentStatus? local;
        try {
          local = await _consent.loadLocalStatus(stillCurrent: current);
        } on Object {
          if (!current()) return;
        }
        if (current()) {
          setState(() {
            _local = local;
            _status = _failure(error.code);
          });
        }
      }
    } on Object {
      if (current()) {
        setState(
          () => _status = 'ยังยืนยันการดำเนินการไม่ได้ โปรดตรวจสอบอีกครั้ง',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  String _failure(ResearchTransportFailureCode code) => switch (code) {
    ResearchTransportFailureCode.notEnrolled =>
      'ยังไม่มีการลงทะเบียน Study จากหน่วยงานสำหรับบัญชีนี้',
    ResearchTransportFailureCode.accountRequired ||
    ResearchTransportFailureCode.ownerChanged =>
      'บัญชีหรือผู้เรียนเปลี่ยนแล้ว โปรดเปิดหน้านี้ใหม่',
    ResearchTransportFailureCode.withdrawalPending =>
      'การถอนในเครื่องมีผลแล้ว การยืนยันกับเซิร์ฟเวอร์ยังไม่สำเร็จ กดถอนสิทธิ์อีกครั้งเพื่อตรวจสอบ',
    ResearchTransportFailureCode.conflict =>
      'สถานะสิทธิ์เปลี่ยนแล้ว โปรดตรวจสอบข้อมูลล่าสุด',
    _ => 'ยังยืนยันสิทธิ์ Study ไม่ได้ การเรียนทั่วไปยังใช้ได้',
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      setState(_invalidate);
    } else if (!_retired) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    _consent.retirePending();
    unawaited(_bindings?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enrollment = _enrollment;
    final local = _local;
    final notice = widget.notice;
    final noticeSha = notice?.contentSha256;
    final renderedBinding = _consent.currentBinding();
    final renderedGeneration = _generation;
    final activation = widget.participationActivation;
    bool renderedCurrent() =>
        renderedBinding != null &&
        _current(renderedGeneration, renderedBinding) &&
        identical(_enrollment, enrollment) &&
        identical(_local, local) &&
        widget.notice?.contentSha256 == noticeSha &&
        identical(widget.participationActivation, activation);
    final noticeMatches =
        notice != null &&
        enrollment != null &&
        notice.version == enrollment.consentVersion &&
        notice.protocolVersion == enrollment.protocolVersion;
    return Scaffold(
      appBar: AppBar(title: const Text('สิทธิ์เข้าร่วม Study')),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Study เป็นทางเลือก การตรวจสิทธิ์ไม่ลงทะเบียนหรือส่งคำตอบให้อัตโนมัติ การเรียนทั่วไปยังใช้ได้',
            ),
            if (enrollment != null) ...[
              const SizedBox(height: 16),
              Text('ฉบับความยินยอม ${enrollment.consentVersion}'),
              Text(
                local?.withdrawnAtUtc != null
                    ? 'ถอนการเข้าร่วมฉบับนี้แล้ว'
                    : local?.accepted == true
                    ? 'มีการตัดสินใจเข้าร่วมในเครื่อง'
                    : 'ยังไม่ได้ยืนยันเข้าร่วมฉบับนี้',
              ),
              if (noticeMatches) ...[
                const SizedBox(height: 16),
                Text(
                  notice.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(notice.body),
                CheckboxListTile(
                  value: _reviewed,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _busy || _retired || local?.withdrawnAtUtc != null
                      ? null
                      : (value) {
                          if (!renderedCurrent()) return;
                          setState(() {
                            _reviewed = value == true;
                            _reviewedNoticeSha = _reviewed ? noticeSha : null;
                          });
                        },
                  title: const Text(
                    'ฉันได้อ่านข้อมูลประกอบการตัดสินใจฉบับนี้แล้ว',
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'ยังไม่มีเอกสารความยินยอมที่ตรงกับ Study ฉบับนี้ จึงยังยืนยันเข้าร่วมไม่ได้',
                  ),
                ),
              FilledButton(
                key: const ValueKey('research-authority-accept'),
                onPressed:
                    _busy ||
                        _retired ||
                        !_reviewed ||
                        _reviewedNoticeSha != noticeSha ||
                        !noticeMatches ||
                        local == null ||
                        local.withdrawnAtUtc != null
                    ? null
                    : () {
                        if (!renderedCurrent() ||
                            !_reviewed ||
                            _reviewedNoticeSha != noticeSha) {
                          return;
                        }
                        unawaited(
                          _command(
                            (current) =>
                                _consent.accept(local, stillCurrent: current),
                            'เซิร์ฟเวอร์ยืนยันการตัดสินใจแล้ว',
                          ),
                        );
                      },
                child: const Text('ยืนยันการตัดสินใจเข้าร่วม'),
              ),
            ],
            if (local != null &&
                (enrollment != null ||
                    local.accepted ||
                    local.withdrawnAtUtc != null))
              OutlinedButton(
                key: const ValueKey('research-authority-withdraw'),
                onPressed: _busy || _retired
                    ? null
                    : () {
                        if (!renderedCurrent()) return;
                        unawaited(
                          _command(
                            (current) => _consent.withdraw(
                              local,
                              widget.nowUtc?.call() ?? DateTime.now().toUtc(),
                              stillCurrent: current,
                            ),
                            'เซิร์ฟเวอร์ยืนยันการถอนแล้ว',
                          ),
                        );
                      },
                child: const Text('ถอนสิทธิ์หรือยืนยันการถอนเดิม'),
              ),
            OutlinedButton(
              key: const ValueKey('research-authority-refresh'),
              onPressed: _busy || _retired || local?.accepted != true
                  ? null
                  : () {
                      if (!renderedCurrent()) return;
                      unawaited(
                        _command(
                          (current) =>
                              _authority.refresh(stillCurrent: current),
                          'ตรวจสิทธิ์ Study ปัจจุบันแล้ว',
                        ),
                      );
                    },
              child: const Text('ตรวจสิทธิ์ Study ปัจจุบัน'),
            ),
            if (activation != null)
              OutlinedButton(
                key: const ValueKey('research-authority-activate'),
                onPressed:
                    _busy ||
                        _retired ||
                        local?.accepted != true ||
                        !_authority.readGate.isOpen ||
                        renderedBinding == null
                    ? null
                    : () {
                        if (!renderedCurrent()) return;
                        unawaited(
                          _command(
                            (current) => activation.activate(
                              expectedBinding: renderedBinding,
                              stillCurrent: current,
                            ),
                            'เปิดใช้ Study ที่ได้รับสิทธิ์ในเครื่องแล้ว',
                          ),
                        );
                      },
                child: const Text('เปิดใช้ Study ที่ได้รับสิทธิ์ในเครื่อง'),
              ),
            TextButton(
              onPressed: _busy || _retired ? null : _load,
              child: const Text('โหลดสถานะล่าสุด'),
            ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังตรวจสอบสิทธิ์ Study',
              ),
            if (_status != null)
              Semantics(liveRegion: true, child: Text(_status!)),
          ],
        ),
      ),
    );
  }
}
