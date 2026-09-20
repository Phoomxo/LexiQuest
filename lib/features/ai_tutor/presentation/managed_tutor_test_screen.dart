import 'dart:async';
import 'package:flutter/material.dart';
import '../../../navigation/app_routes.dart';
import '../application/managed_tutor_host.dart';
import '../data/local_login_bridge.dart';
import '../domain/ai_tutor_contracts.dart';
import 'managed_tutor_panel.dart';
import 'managed_practice_card.dart';
import '../application/managed_tutor_controller.dart';

/// Explicit developer-test composition only. No provider account identifiers.
class ManagedTutorTestScreen extends StatefulWidget {
  const ManagedTutorTestScreen({
    super.key,
    required this.host,
    required this.bridge,
    required this.openLogin,
    this.loadWords,
    this.embedded = false,
  });
  final Future<List<Map<String, dynamic>>> Function()? loadWords;
  final bool embedded;
  final ManagedTutorHost host;
  final LocalLoginBridge bridge;
  final Future<void> Function(Uri) openLogin;
  @override
  State<ManagedTutorTestScreen> createState() => _ManagedTutorTestScreenState();
}

class _ManagedTutorTestScreenState extends State<ManagedTutorTestScreen>
    with WidgetsBindingObserver, RouteAware {
  DeviceLoginChallenge? _challenge;
  String _status = 'ยังไม่ได้เชื่อมบัญชี';
  bool _busy = false;
  bool _privateLogin = false;
  int _epoch = 0;
  Future<void> _work = Future.value();
  PageRoute<dynamic>? _route;
  List<Map<String, dynamic>> _words = [];
  String? _selectedId;
  int _wordsEpoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.identity.addListener(_ownerChanged);
    widget.host.controller.addListener(_chatChanged);
    unawaited(_loadWords());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = widget.embedded ? null : ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  void _chatChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWords() async {
    final epoch = ++_wordsEpoch;
    try {
      final words = await widget.loadWords?.call() ?? <Map<String, dynamic>>[];
      if (!mounted || epoch != _wordsEpoch) return;
      setState(() => _words = words);
    } on Object {
      if (mounted && epoch == _wordsEpoch) setState(() => _words = []);
    }
  }

  void _ownerChanged() {
    _words = [];
    _selectedId = null;
    widget.bridge.selectedWord = null;
    _disconnect();
    unawaited(_loadWords());
  }

  Future<void> _clearBridge() async {
    try {
      await widget.bridge.disconnect();
    } on Object {
      /* Fixed UI message only. */
    }
  }

  void _disconnect() {
    _epoch++;
    _privateLogin = false;
    _challenge = null;
    _busy = false;
    widget.host.disconnect();
    // A late /login must finish before /disconnect; never resurrect its code.
    _work = _work.then((_) => _clearBridge());
    if (mounted) {
      setState(() {
        _status = 'ตัดการเชื่อมต่อในเครื่องแล้ว (ไม่ใช่ถอนสิทธิ์จาก OpenAI)';
      });
    }
  }

  Future<void> _login() async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _challenge = null;
      _status = 'กำลังขอการเชื่อมต่อ';
    });
    try {
      final challenge = await widget.bridge.login();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _challenge = challenge;
        _privateLogin = true;
        _status = 'กรอกรหัสนี้บนหน้า OpenAI ด้วยตนเอง แล้วกลับมาตรวจสถานะ';
      });
    } on Object catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _status =
            error is AiTutorException && error.code == AiFailureCode.offline
            ? 'ออฟไลน์หรือสะพานทดสอบไม่พร้อม กรุณาเชื่อม USB อีกครั้ง'
            : 'การเชื่อมต่อไม่สำเร็จหรือหมดเวลา ลองเชื่อมบัญชีใหม่';
      });
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _check() async {
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _privateLogin = false;
      _challenge = null;
    });
    try {
      final authenticated = await widget.bridge.status();
      if (!mounted || epoch != _epoch) return;
      if (authenticated && widget.bridge.inferenceEnabled) {
        await widget.host.connect();
        if (!mounted || epoch != _epoch) return;
      }
      setState(() {
        _status = authenticated
            ? (widget.bridge.inferenceEnabled
                  ? 'เชื่อมบัญชีแล้ว ดูสถานะห้องสนทนาด้านล่าง'
                  : 'เชื่อมบัญชีแล้ว — ยังไม่เปิดการส่งคำถามจริง')
            : 'ยังไม่เชื่อมบัญชี หรือรหัสหมดอายุ กรุณาเชื่อมใหม่';
      });
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(() {
          _status = 'ตรวจสถานะไม่ได้ กรุณาตรวจสะพานทดสอบ';
        });
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.host.setForeground(state == AppLifecycleState.resumed);
    // Explicit OpenAI browser handoff may remain pending until user returns.
    // No polling/DOM/capture/account reads run in this interval.
    if (state != AppLifecycleState.resumed && !_privateLogin) _disconnect();
  }

  @override
  void didPushNext() {
    widget.host.setVisible(false);
    _disconnect();
  }

  @override
  void didPopNext() => widget.host.setVisible(true);
  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    widget.host.identity.removeListener(_ownerChanged);
    widget.host.controller.removeListener(_chatChanged);
    widget.host.dispose();
    unawaited(
      _work.then((_) => _clearBridge()).whenComplete(widget.bridge.dispose),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(title: const Text('อารี · ห้องสนทนาทดสอบ')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('รุ่นทดสอบผ่าน USB และเครื่องพัฒนาเฉพาะรอบนี้'),
          const SizedBox(height: 12),
          const Text(
            'Device-code เป็น beta ต้องเปิดใน ChatGPT security settings ก่อนใช้งาน',
          ),
          const Text('สนทนาและฝึกคำศัพท์กับอารี ผลการฝึกรอบนี้ไม่เพิ่มคะแนน'),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_status)),
          if (_busy) const LinearProgressIndicator(),
          if (_challenge case final DeviceLoginChallenge challenge) ...[
            const SizedBox(height: 16),
            Text(
              challenge.userCode,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await widget.openLogin(challenge.verificationUrl);
                      } on Object {
                        if (mounted) {
                          setState(() {
                            _status = 'เปิดเบราว์เซอร์ไม่ได้ กรุณาลองอีกครั้ง';
                          });
                        }
                      }
                    },
              child: const Text('เปิดหน้า OpenAI'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      _work = _check();
                    },
              child: const Text('กรอกเสร็จแล้ว ตรวจสถานะ'),
            ),
          ],
          if (_challenge == null)
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      _work = _work.then((_) => _login());
                    },
              child: const Text('เชื่อมบัญชี ChatGPT'),
            ),
          if (_challenge == null)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      _work = _work.then((_) => _check());
                    },
              child: const Text('เปิดห้องสนทนา'),
            ),
          TextButton(
            onPressed: _disconnect,
            child: Text(_busy || _privateLogin ? 'ยกเลิก' : 'ออกจากระบบทดสอบ'),
          ),
          const Divider(height: 32),
          if (_words.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedId),
              initialValue: _selectedId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'เลือกคำศัพท์ให้ช่วย',
              ),
              items: _words
                  .map(
                    (w) => DropdownMenuItem<String>(
                      value: w['id'] as String,
                      child: Text(w['spelling'] as String),
                    ),
                  )
                  .toList(),
              onChanged:
                  _busy ||
                      widget.host.controller.state == ManagedTutorState.replying
                  ? null
                  : (id) {
                      widget.host.disconnect();
                      setState(() {
                        _selectedId = id;
                        widget.bridge.toolResults = const [];
                        widget.bridge.selectedWord = _words.firstWhere(
                          (w) => w['id'] == id,
                        );
                        _status =
                            'เลือกคำแล้ว กดเปิดห้องสนทนาเพื่อเริ่มบทสนทนาใหม่';
                      });
                    },
            ),
          const Text(
            'อารีใช้คำศัพท์ที่เลือกและข้อมูลเมนูที่เปิดอยู่ การเปลี่ยนคำจะเริ่มบทสนทนาใหม่',
          ),
          ManagedTutorPanel(controller: widget.host.controller),
          if (widget.host.controller.state == ManagedTutorState.ready)
            for (final receipt in widget.bridge.toolResults)
              if (receipt['name'] == 'create_practice_draft' &&
                  widget.bridge.selectedWord != null)
                ManagedPracticeCard(
                  word: widget.bridge.selectedWord!,
                  receipt: receipt,
                )
              else
                Text(
                  receipt['status'] == 'completed'
                      ? 'เครื่องมือ ${receipt['name']}: ${receipt['data']['status'] ?? 'สำเร็จ'}'
                      : 'เครื่องมือ ${receipt['name']}: ไม่สำเร็จ',
                ),
        ],
      ),
    ),
  );
}
