import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import 'vocabulary_browse_lifetime.dart';

bool sameDeleteWord(VocabularyWord a, VocabularyWord b) =>
    a.id == b.id &&
    a.ownerId == b.ownerId &&
    a.categoryId == b.categoryId &&
    a.localRevision == b.localRevision &&
    a.spelling == b.spelling &&
    a.meaning == b.meaning &&
    !a.isDeleted &&
    !a.isReadOnly;

/// Owns only the existing explicit delete confirmation. All writes still pass
/// through VocabularyUseCases and the canonical repository.
class WordDeleteDialog extends StatefulWidget {
  const WordDeleteDialog({
    super.key,
    required this.vocabulary,
    required this.word,
    required this.read,
    required this.admitted,
    required this.reconcileAdmitted,
    required this.changes,
  });
  final VocabularyUseCases vocabulary;
  final VocabularyWord word;
  final VocabularyBrowseRead<VocabularyWord> read;
  final bool Function() admitted;
  final bool Function() reconcileAdmitted;
  final Listenable changes;
  @override
  State<WordDeleteDialog> createState() => _WordDeleteDialogState();
}

class _WordDeleteDialogState extends State<WordDeleteDialog>
    with WidgetsBindingObserver {
  bool _retired = false, _ownerRetired = false, _closed = false;
  bool _busy = false, _reading = false, _attempted = false;
  int _generation = 0, _viewEpoch = 0;
  int? _categoryRevision;
  String? _error;
  Future<void>? _ready;
  StreamSubscription<List<VocabularyCategory>>? _categories;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.changes.addListener(_changed);
    widget.read.addListener(_changed);
  }

  void _render() {
    if (!mounted || _closed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closed) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (widget.read.ownerId != null &&
        widget.read.ownerId != widget.word.ownerId)
      _ownerRetired = true;
    if (!widget.admitted() ||
        _ownerRetired ||
        !widget.read.available ||
        (!_busy &&
            !_attempted &&
            widget.read.data != null &&
            !widget.read.data!.any((w) => sameDeleteWord(w, widget.word)))) {
      _retired = true;
      _viewEpoch++;
    }
    _render();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false ||
        !TickerMode.valuesOf(context).enabled) {
      _retired = true;
      _viewEpoch++;
    }
    _ready ??= _read();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _retired = true;
    _viewEpoch++;
    _render();
  }

  bool get _visible =>
      mounted &&
      !_closed &&
      ModalRoute.of(context)?.isCurrent == true &&
      TickerMode.valuesOf(context).enabled;
  bool get _current =>
      _visible && !_retired && !_ownerRetired && widget.admitted();
  bool get _readCurrent =>
      _visible &&
      !_ownerRetired &&
      widget.reconcileAdmitted() &&
      widget.read.ownerId == widget.word.ownerId;

  Future<bool> _owner({bool readOnly = false}) async {
    bool current() => readOnly ? _readCurrent : _current;
    if (!current()) return false;
    final owner = await widget.vocabulary.owners.getOrCreateActiveOwner();
    if (!current()) return false;
    if (owner.id != widget.word.ownerId) {
      _ownerRetired = true;
      _retired = true;
      _viewEpoch++;
      _render();
      return false;
    }
    return true;
  }

  Future<void> _read() async {
    if (_reading || _closed) return;
    _reading = true;
    try {
      if (!await _owner()) return;
      final categories = await widget.vocabulary.vocabulary
          .watchCategories(widget.word.ownerId)
          .first;
      final category = categories
          .where(
            (c) =>
                c.id == widget.word.categoryId &&
                c.ownerId == widget.word.ownerId &&
                !c.isDeleted &&
                !c.isReadOnly,
          )
          .firstOrNull;
      if (!await _owner()) return;
      if (category == null) {
        _retired = true;
        return;
      }
      _categoryRevision = category.localRevision;
      _error = null;
      _categories ??= widget.vocabulary.vocabulary
          .watchCategories(widget.word.ownerId)
          .listen(
            (rows) {
              if (_closed || !mounted) return;
              if (!rows.any(
                (c) =>
                    c.id == widget.word.categoryId &&
                    c.ownerId == widget.word.ownerId &&
                    c.localRevision == _categoryRevision &&
                    !c.isDeleted,
              )) {
                _retired = true;
                _viewEpoch++;
                _render();
              }
            },
            onError: (Object e) {
              if (mounted && !_closed) {
                _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
                _render();
              }
            },
          );
    } catch (_) {
      if (mounted && !_closed)
        _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
    } finally {
      _reading = false;
      _render();
    }
  }

  void _close(int generation) {
    if (generation != _generation || !_visible) return;
    _closed = true;
    Navigator.pop(context);
  }

  Future<Map<String, Object?>> _verify(bool Function() allowed) async {
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    final remaining = await widget.vocabulary.vocabulary.listAllWords(
      widget.word.ownerId,
    );
    if (!await _owner(readOnly: true) || !allowed()) return {'status': 'stale'};
    if (remaining.any((w) => w.id == widget.word.id))
      return {'status': 'verification_failed'};
    _close(_generation);
    return {'status': 'deleted', 'wordId': widget.word.id};
  }

  Future<Map<String, Object?>> _delete(
    int generation, {
    bool optional = false,
  }) async {
    if (generation != _generation ||
        _busy ||
        (_attempted ? !_readCurrent : !_current))
      return {'status': 'stale'};
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    final session = registry?.sessionGeneration;
    final epoch = _viewEpoch;
    bool allowed() =>
        _current &&
        (!optional ||
            registry?.currentOwner() == widget.word.ownerId &&
                registry?.snapshot()['revision'] == revision);
    bool verifyAllowed() =>
        _readCurrent &&
        epoch == _viewEpoch &&
        (!optional ||
            registry?.currentOwner() == widget.word.ownerId &&
                registry?.sessionGeneration == session);
    if (optional && registry?.currentOwner() != widget.word.ownerId)
      return {'status': 'stale'};
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ready;
      if (_attempted) return await _verify(verifyAllowed);
      if (!await _owner() || !allowed()) return {'status': 'stale'};
      if (_categoryRevision == null) {
        _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
        return {'status': 'failed'};
      }
      final words = await widget.vocabulary.vocabulary
          .watchWords(widget.word.ownerId, widget.word.categoryId)
          .first;
      final categories = await widget.vocabulary.vocabulary
          .watchCategories(widget.word.ownerId)
          .first;
      if (!await _owner() || !allowed()) return {'status': 'stale'};
      if (!words.any((w) => sameDeleteWord(w, widget.word)) ||
          !categories.any(
            (c) =>
                c.id == widget.word.categoryId &&
                c.ownerId == widget.word.ownerId &&
                c.localRevision == _categoryRevision &&
                !c.isDeleted &&
                !c.isReadOnly,
          )) {
        _retired = true;
        return {'status': 'stale'};
      }
      _attempted = true;
      await widget.vocabulary.deleteWord(
        widget.word.id,
        expectedOwnerId: widget.word.ownerId,
        mutationAllowed: allowed,
        expectedWord: widget.word,
        expectedCategoryRevision: _categoryRevision,
      );
      return await _verify(verifyAllowed);
    } on InvalidVocabularyFailure catch (e) {
      if (e.field == 'owner') {
        _retired = true;
        _ownerRetired = true;
        return {'status': 'stale'};
      }
      return {'status': 'invalid'};
    } catch (_) {
      // A failed acknowledgement alone does not prove rollback. Only a fresh
      // owner-checked read of the unchanged word permits another explicit try.
      var unchanged = false;
      if (_attempted) {
        try {
          if (await _owner(readOnly: true) && verifyAllowed()) {
            final records = await widget.vocabulary.vocabulary.listAllWords(
              widget.word.ownerId,
            );
            unchanged =
                await _owner(readOnly: true) &&
                verifyAllowed() &&
                records.any((w) => sameDeleteWord(w, widget.word));
          }
        } catch (_) {
          // Keep the uncertain outcome and never automatically resubmit.
        }
      }
      if (_readCurrent)
        _error = _attempted
            ? 'ยังยืนยันผลการลบไม่ได้ กรุณาตรวจสอบรายการคำศัพท์ก่อนลองใหม่'
            : 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
      if (unchanged) _attempted = false;
      return {'status': _attempted ? 'outcome_unknown' : 'failed'};
    } finally {
      _busy = false;
      _render();
    }
  }

  @override
  void dispose() {
    _closed = true;
    widget.changes.removeListener(_changed);
    widget.read.removeListener(_changed);
    _categories?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    final privateVisible =
        !_ownerRetired &&
        widget.read.available &&
        !widget.read.pending &&
        (_attempted ? _readCurrent : _current);
    void close() => _close(generation);
    final dialog = AlertDialog(
      title: const Text('ลบคำศัพท์'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              !privateVisible
                  ? 'บริบทเปลี่ยนแล้ว กรุณาปิดและเปิดใหม่'
                  : _attempted
                  ? (_error ??
                        'ยังยืนยันผลการลบไม่ได้ ปิดหน้าต่างนี้เพื่อตรวจสอบรายการคำศัพท์')
                  : 'ลบ “${widget.word.spelling}” (${widget.word.meaning}) หรือไม่',
            ),
            if (_reading || _busy) const LinearProgressIndicator(),
            if (_error != null && privateVisible && !_attempted) Text(_error!),
            if (_error != null && !_attempted && _current)
              TextButton(
                onPressed: _reading || _busy
                    ? null
                    : () {
                        if (generation != _generation || !_current) return;
                        _ready = _read();
                      },
                child: const Text('ลองใหม่'),
              ),
          ],
        ),
      ),
      actions: [
        MenuActionBinding(
          id: 'vocabulary/word-delete-cancel',
          label: _attempted ? 'ปิดผลการลบคำศัพท์' : 'ยกเลิกการลบคำศัพท์',
          ownerId: widget.word.ownerId,
          onInvoke: close,
          child: TextButton(
            onPressed: close,
            child: Text(_attempted ? 'ปิด' : 'ยกเลิก'),
          ),
        ),
        FilledButton(
          onPressed: _busy || _attempted || !_current
              ? null
              : () => _delete(generation),
          child: const Text('ลบ'),
        ),
      ],
    );
    if (!privateVisible) return dialog;
    return MenuActionBinding(
      id: 'vocabulary/word-delete-target',
      label: '${widget.word.spelling} — ${widget.word.meaning}',
      ownerId: widget.word.ownerId,
      onInvoke: null,
      readValue: widget.word.id,
      child: MenuActionBinding(
        id: 'vocabulary/word-delete-confirm',
        label: 'ยืนยันลบคำ ${widget.word.spelling}',
        ownerId: widget.word.ownerId,
        onInvoke: null,
        fields: const {'wordId': 256},
        onForm: (values) async {
          if (values['wordId'] != widget.word.id) return {'status': 'invalid'};
          return _delete(generation, optional: true);
        },
        child: dialog,
      ),
    );
  }
}
