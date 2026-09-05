import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/research_participation_permit.dart';

/// Displays only a caller-validated permit; pasted input grants no authority.
class ResearchParticipationPanel extends StatefulWidget {
  const ResearchParticipationPanel({
    super.key,
    this.permit,
    required this.onImport,
    required this.onWithdraw,
    required this.onContinueLearning,
    this.languageCode = 'th',
  });

  /// Must be validated externally for the current owner, receipts, revision,
  /// expiry and revocation. Pass null whenever that authority is unavailable.
  final ResearchParticipationPermit? permit;
  final Future<void> Function(String signedDocument) onImport;
  final Future<void> Function() onWithdraw;
  final VoidCallback onContinueLearning;
  final String languageCode;

  @override
  State<ResearchParticipationPanel> createState() =>
      _ResearchParticipationPanelState();
}

enum _Action { paste, import, withdraw }

enum _Status { idle, pending, invalidDocument, failure, imported, withdrawn }

class _ResearchParticipationPanelState
    extends State<ResearchParticipationPanel> {
  final _document = TextEditingController();
  bool _busy = false;
  bool _withdrawn = false;
  int _generation = 0;
  _Action? _retryAction;
  _Status _status = _Status.idle;

  bool get _thai => widget.languageCode != 'en';
  String _text(String th, String en) => _thai ? th : en;

  @override
  void didUpdateWidget(covariant ResearchParticipationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.permit, widget.permit)) {
      _generation++;
      if (oldWidget.permit?.id != widget.permit?.id ||
          oldWidget.permit?.ownerId != widget.permit?.ownerId ||
          oldWidget.permit?.localRevision != widget.permit?.localRevision ||
          oldWidget.permit?.cloudRevision != widget.permit?.cloudRevision) {
        _withdrawn = false;
      }
      _document.clear();
      _retryAction = null;
      _status = _busy ? _Status.pending : _Status.idle;
    }
  }

  @override
  void dispose() {
    _generation++;
    _retryAction = null;
    _document.clear();
    _document.dispose();
    super.dispose();
  }

  bool _isDocument(String text) {
    if (text.trim().isEmpty || utf8.encode(text).length > 16 * 1024) {
      return false;
    }
    try {
      // Syntax/size only. No signature, receipt or consent decisions occur here.
      return jsonDecode(text) is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      // An explicit paste action preserves the entire externally signed
      // document, including newlines stripped by single-line input formatters.
      final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      if (!mounted || generation != _generation) return;
      if (utf8.encode(value).length > 16 * 1024) {
        _document.clear();
        setState(() => _status = _Status.invalidDocument);
      } else {
        _document.text = value;
        setState(() => _status = _Status.idle);
      }
      _retryAction = null;
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _status = _Status.failure;
          _retryAction = _Action.paste;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final document = _document.text;
    if (!_isDocument(document)) {
      setState(() {
        _status = _Status.invalidDocument;
        _retryAction = null;
      });
      return;
    }
    await _perform(_Action.import, () => widget.onImport(document));
  }

  Future<void> _withdraw() async {
    if (_busy || _withdrawn) return;
    await _perform(_Action.withdraw, widget.onWithdraw);
  }

  Future<void> _perform(
    _Action action,
    Future<void> Function() callback,
  ) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _status = _Status.pending;
      _retryAction = null;
    });
    try {
      await callback();
      if (!mounted || generation != _generation) return;
      _document.clear();
      if (action == _Action.withdraw) _withdrawn = true;
      setState(
        () => _status = action == _Action.import
            ? _Status.imported
            : _Status.withdrawn,
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _status = _Status.failure;
          _retryAction = action;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (generation != _generation) _status = _Status.idle;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permit = widget.permit;
    final verified =
        permit != null &&
        !permit.isDeleted &&
        permit.revokedAtUtc == null &&
        !_withdrawn;
    final adult =
        verified && permit.participantClass == ResearchParticipantClass.adult;
    final externallyVerified = _text(
      'ยืนยันจากภายนอกแล้ว',
      'Verified externally',
    );
    final notReady = _text('ยังไม่พร้อม', 'Not ready');
    final notRequired = _text(
      'ไม่จำเป็นสำหรับ adult',
      'Not required for adult',
    );
    final guardian = adult
        ? notRequired
        : verified && (permit.guardianPermissionReceiptRef?.isNotEmpty ?? false)
        ? externallyVerified
        : notReady;
    final assent = adult
        ? notRequired
        : verified && (permit.learnerAssentReceiptRef?.isNotEmpty ?? false)
        ? externallyVerified
        : notReady;
    final status = switch (_status) {
      _Status.idle => _text(
        'ใช้เอกสารที่ลงนามจากภายนอกเท่านั้น สถานะขึ้นกับผลการยืนยันจากผู้รับผิดชอบ',
        'Use an externally signed document. Participation depends on external verification.',
      ),
      _Status.pending => _text(
        'กำลังบันทึก คุณยังเรียนต่อได้',
        'Saving. You can continue learning.',
      ),
      _Status.invalidDocument => _text(
        'วางเอกสาร JSON แบบออบเจ็กต์ขนาดไม่เกิน 16 KB',
        'Paste a JSON object document of no more than 16 KB.',
      ),
      _Status.failure => _text(
        'บันทึกไม่สำเร็จ ลองอีกครั้งได้',
        'Could not save. You can retry.',
      ),
      _Status.imported => _text(
        'ส่งเอกสารแล้ว สถานะการเข้าร่วมขึ้นกับการยืนยันจากภายนอก',
        'Document submitted. Participation depends on external verification.',
      ),
      _Status.withdrawn => _text(
        'หยุดเข้าร่วมแล้ว คุณเรียนต่อได้',
        'Participation stopped. You can continue learning.',
      ),
    };
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return FocusTraversalGroup(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  _text(
                    'การเข้าร่วมการวิจัย (ไม่บังคับ)',
                    'Optional research participation',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _text(
                  'คุณเลือกเข้าร่วมหรือข้ามได้ และถอนตัวได้ภายหลัง ไม่กระทบการเรียน',
                  'Taking part is optional. You may skip or withdraw later; this does not affect learning.',
                ),
              ),
              const SizedBox(height: 12),
              if (permit != null)
                Text(
                  _text('กลุ่มผู้เข้าร่วม: ', 'Participant group: ') +
                      permit.participantClass.name,
                ),
              Text(
                _text('ความยินยอม: ', 'Consent: ') +
                    (verified ? externallyVerified : notReady),
              ),
              Text(
                _text('การอนุญาตของผู้ปกครอง: ', 'Guardian permission: ') +
                    guardian,
              ),
              Text(
                _text('ความสมัครใจของผู้เรียน: ', 'Learner assent: ') + assent,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('research-participation-continue'),
                style: buttonStyle,
                onPressed: widget.onContinueLearning,
                child: Text(_text('เรียนต่อ', 'Continue learning')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('research-participation-skip'),
                style: buttonStyle,
                onPressed: widget.onContinueLearning,
                child: Text(_text('ข้าม', 'Skip')),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('research-participation-paste'),
                style: buttonStyle,
                onPressed: _busy ? null : () => unawaited(_paste()),
                child: Text(_text('วางเอกสาร', 'Paste document')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _document,
                enabled: !_busy,
                readOnly: true,
                enableInteractiveSelection: false,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: _text(
                    'เอกสาร JSON ที่ลงนามจากภายนอก',
                    'Externally signed JSON document',
                  ),
                  helperText: _text(
                    'วางเอกสารขนาดไม่เกิน 16 KB',
                    'Paste a document up to 16 KB',
                  ),
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('research-participation-import'),
                style: buttonStyle,
                onPressed: _busy ? null : () => unawaited(_import()),
                child: Text(_text('นำเข้าเอกสาร', 'Import document')),
              ),
              const SizedBox(height: 12),
              Semantics(
                key: const ValueKey('research-participation-status'),
                label: status,
                liveRegion: true,
                child: ExcludeSemantics(child: Text(status)),
              ),
              if (_retryAction != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('research-participation-retry'),
                  style: buttonStyle,
                  onPressed: _busy
                      ? null
                      : () => unawaited(switch (_retryAction) {
                          _Action.paste => _paste(),
                          _Action.import => _import(),
                          _Action.withdraw => _withdraw(),
                          null => Future<void>.value(),
                        }),
                  child: Text(_text('ลองอีกครั้ง', 'Retry')),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('research-participation-withdraw'),
                style: buttonStyle,
                onPressed: _busy || permit == null || _withdrawn
                    ? null
                    : () => unawaited(_withdraw()),
                child: Text(
                  _text('ถอนตัวจากการวิจัย', 'Withdraw from research'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
