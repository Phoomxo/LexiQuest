import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../../../screens/saved_words_screen.dart';
import '../../../screens/srs_flashcards_screen.dart';
import '../../../screens/quiz_screen.dart';
import '../../../voice/voice_models.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../../../widgets/word_report_sheet.dart';
import '../../content_reports/domain/content_report.dart';
import '../../content_reports/presentation/content_report_button.dart';
import '../../learning/domain/learning_time_admission.dart';
import '../../vocabulary/application/word_report_use_cases.dart';
import '../../vocabulary/domain/word_report.dart';
import '../../voice/application/voice_use_cases.dart';
import '../../learning/domain/accepted_quiz_plan.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/presentation/lexical_quiz_setup_dialog.dart';
import '../application/learning_pack_use_cases.dart';
import 'rich_lexical_card.dart';
import '../data/bundled_starter_pack.dart';
import '../data/http_learning_pack_source.dart';
import '../domain/learning_pack.dart';
import '../domain/learning_pack_download.dart';
import '../domain/learning_pack_repository.dart';

typedef LearningPackFilePicker = Future<XFile?> Function();

class LearningPackCatalogScreen extends StatefulWidget {
  const LearningPackCatalogScreen({
    super.key,
    this.packs,
    this.downloads,
    this.pickFile,
    this.voice,
    this.openStarterPreview = false,
  });
  final LearningPackUseCases? packs;
  final HttpLearningPackSource? downloads;
  final LearningPackFilePicker? pickFile;
  final VoiceUseCases? voice;
  final bool openStarterPreview;

  @override
  State<LearningPackCatalogScreen> createState() => _LearningPackCatalogState();
}

class _LearningPackCatalogState extends State<LearningPackCatalogScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  LearningPackUseCases? _packs;
  HttpLearningPackSource? _downloads;
  VoiceUseCases? _voice;
  WordReportUseCases? _reports;
  SavedWordsViewBinding? _saved;
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _owners;
  PackOwnerScope? _scope;
  List<StoredLearningPack> _rows = const [];
  _PackView _view = const _Catalog();
  _PendingPackWrite? _pending;
  ModalRoute<dynamic>? _route;
  Route<dynamic>? _practiceRoute;
  Route<dynamic>? _practiceChildRoute;
  Completer<void>? _pickerResumed;
  String _cefr = 'all';
  String? _status;
  int _lease = 0;
  int _operation = 0;
  int? _received;
  int? _expected;
  bool _bound = false;
  bool _retired = false;
  bool _busy = false;
  bool _picker = false;
  bool _overlay = false;
  bool _ownsPlayback = false;
  bool _foreground = true;
  bool _covered = false;
  bool _openStarterPending = false;

  bool get _visible =>
      mounted &&
      !_retired &&
      (_foreground || _picker) &&
      ((_route?.isCurrent ?? true) ||
          _overlay ||
          _practiceRoute?.isCurrent == true ||
          _practiceChildRoute?.isCurrent == true);
  bool get _canAct =>
      _visible &&
      (_route?.isCurrent ?? true) &&
      !_picker &&
      !_busy &&
      _pending == null &&
      _packs != null;
  bool _current(int lease) => _visible && lease == _lease;
  bool _operationCurrent(int operation) =>
      mounted && !_retired && operation == _operation;
  bool _resultCurrent(int operation, PackOwnerScope? scope) =>
      _operationCurrent(operation) && (scope == null || scope.isCurrent);

  VoidCallback? _action(VoidCallback action) {
    if (!_canAct) return null;
    final lease = _lease;
    final scope = _scope;
    final view = _view;
    return () {
      if (_canAct &&
          lease == _lease &&
          identical(scope, _scope) &&
          identical(view, _view)) {
        action();
      }
    };
  }

  VoidCallback? _retryAction() {
    final pending = _pending;
    final scope = _scope;
    final lease = _lease;
    if (_busy || pending == null || scope?.isCurrent != true) return null;
    return () {
      if (!_busy &&
          _visible &&
          lease == _lease &&
          identical(scope, _scope) &&
          identical(pending, _pending)) {
        unawaited(_applyPending());
      }
    };
  }

  @override
  void initState() {
    super.initState();
    _openStarterPending = widget.openStarterPreview;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final packs = widget.packs ?? dependencies?.learningPacks;
    final voice = widget.voice ?? dependencies?.voice;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _packs = packs;
      _downloads = widget.downloads;
      _voice = voice;
      _reports = dependencies?.wordReports;
      if (dependencies != null &&
          !identical(dependencies.learningPacks, packs)) {
        _retire();
      } else if (packs != null) {
        _owners = packs.watchActiveOwnerId().listen(
          _ownerChanged,
          onError: (Object _) => _retire(),
          onDone: _retire,
        );
      }
    } else if (!identical(dependencies, _dependencies) ||
        !identical(packs, _packs) ||
        !identical(voice, _voice) ||
        !identical(widget.downloads, _downloads)) {
      _retire();
    } else if (!_overlay &&
        _practiceRoute?.isCurrent != true &&
        _practiceChildRoute?.isCurrent != true &&
        _route?.isCurrent == false &&
        !_retired) {
      _covered = true;
      _cancelWork();
    } else if (_covered && _route?.isCurrent == true && !_retired) {
      _covered = false;
      unawaited(_reload());
    }
    _saved?.syncVisibility();
  }

  @override
  void didUpdateWidget(LearningPackCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.packs, oldWidget.packs) ||
        !identical(widget.downloads, oldWidget.downloads) ||
        !identical(widget.voice, oldWidget.voice)) {
      _retire();
    }
  }

  void _ownerChanged(String? owner) {
    if (!mounted || _retired) return;
    final openStarter = _openStarterPending;
    _openStarterPending = false;
    _cancelWork();
    final previous = _saved;
    _saved = null;
    unawaited(previous?.close());
    final savedWords = _dependencies?.savedWords;
    if (owner != null && savedWords != null) {
      _saved = SavedWordsViewBinding(
        useCases: savedWords,
        ownerChanges: _packs!.watchActiveOwnerId(),
        expectedOwnerId: owner,
        visible: () => _visible && _practiceRoute == null,
      )..addListener(_savedChanged);
    }
    if (owner != null) unawaited(_reload(openStarter: openStarter));
  }

  void _savedChanged() {
    if (mounted && !_retired) setState(() {});
  }

  void _cancelWork() {
    _lease++;
    _operation++;
    _practiceChildRoute = null;
    _wakePicker();
    _stopVoice();
    if (!mounted) return;
    setState(() {
      _scope = null;
      _rows = const [];
      _view = const _Catalog();
      _pending = null;
      _busy = false;
      _received = null;
      _expected = null;
      _status = null;
    });
  }

  void _retire() {
    if (_retired) return;
    _cancelWork();
    _retired = true;
    unawaited(_owners?.cancel());
    unawaited(_saved?.close());
    _saved = null;
    if (mounted) {
      setState(
        () =>
            _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดกลับไปเปิดแพ็กบทเรียนใหม่',
      );
    }
  }

  Future<PackOwnerScope?> _capture() {
    final packs = _packs;
    if (packs == null) return Future.value();
    final lease = _lease;
    return packs.captureOwner(stillCurrent: () => _current(lease));
  }

  Future<void> _reload({bool openStarter = false}) async {
    if (!_visible || _packs == null || _busy || _picker) return;
    final operation = ++_operation;
    setState(() => _busy = true);
    final saved = _saved;
    if (saved != null && (saved.readFailed || saved.conflicts.isNotEmpty)) {
      saved.retryRead();
    }
    PackOwnerScope? scope;
    try {
      scope = await _capture();
      if (!_resultCurrent(operation, scope)) return;
      final rows = scope == null
          ? <StoredLearningPack>[]
          : await _packs!.list(scope);
      if (!_resultCurrent(operation, scope)) return;
      setState(() {
        _scope = scope;
        _rows = rows;
        _pending = null;
        _view = openStarter && scope != null
            ? _Preview(
                bundledStarterPack,
                PackSourceDescriptor.configuredCatalog(bundledStarterCatalogId),
              )
            : const _Catalog();
        _status = scope == null ? 'ไม่พบผู้เรียนที่พร้อมใช้งาน' : null;
      });
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<LearningPack?> _pick(PackOwnerScope scope) async {
    final resumed = Completer<void>();
    _pickerResumed = resumed;
    _picker = true;
    XFile? file;
    try {
      file = await (widget.pickFile ?? _pickFile)();
      if (file != null && !_foreground) await resumed.future;
      if (!_foreground || !scope.isCurrent || file == null) return null;
    } finally {
      _picker = false;
      if (identical(_pickerResumed, resumed)) _pickerResumed = null;
    }
    if (!scope.isCurrent) return null;
    if (await file.length() > maxLearningPackBytes) {
      throw const LearningPackException(LearningPackFailureCode.tooLarge);
    }
    if (!scope.isCurrent) return null;
    final bytes = BytesBuilder();
    await for (final chunk in file.openRead()) {
      if (!scope.isCurrent) return null;
      if (bytes.length + chunk.length > maxLearningPackBytes) {
        throw const LearningPackException(LearningPackFailureCode.tooLarge);
      }
      bytes.add(chunk);
    }
    if (!scope.isCurrent) return null;
    final pack = await compute(_decodePack, bytes.takeBytes());
    return scope.isCurrent ? pack : null;
  }

  void _wakePicker() {
    final resumed = _pickerResumed;
    if (resumed != null && !resumed.isCompleted) resumed.complete();
  }

  Future<void> _importFile({StoredLearningPack? repair}) async {
    if (!_canAct) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = null;
    });
    PackOwnerScope? scope;
    try {
      scope = await _capture();
      if (scope == null || !_resultCurrent(operation, scope)) return;
      final pack = await _pick(scope);
      if (pack == null || !_resultCurrent(operation, scope)) return;
      _scope = scope;
      if (repair == null) {
        setState(
          () => _view = _Preview(pack, const PackSourceDescriptor.userFile()),
        );
      } else {
        _pending = _PendingCache(
          _packs!.prepareCacheChange(
            scope: scope,
            stored: repair,
            pinned: repair.isPinned,
            repair: pack,
          ),
        );
      }
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
    if (_resultCurrent(operation, scope) && _pending != null) {
      await _applyPending();
    }
  }

  Future<void> _openStarter() async {
    if (!_canAct) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = null;
    });
    PackOwnerScope? scope;
    try {
      scope = await _capture();
      if (scope == null || !_resultCurrent(operation, scope)) return;
      setState(() {
        _scope = scope;
        _view = _Preview(
          bundledStarterPack,
          PackSourceDescriptor.configuredCatalog(bundledStarterCatalogId),
        );
      });
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  StoredLearningPack? _matching(LearningPack pack) {
    for (final row in _rows) {
      if (row.manifest.packId == pack.manifest.packId &&
          row.manifest.version == pack.manifest.version &&
          row.packageSha256 == pack.packageSha256) {
        return row;
      }
    }
    return null;
  }

  Future<void> _installPreview(
    _Preview preview, {
    required bool install,
  }) async {
    final scope = _scope;
    if (!_canAct || scope == null || !scope.isCurrent) return;
    final existing = _matching(preview.pack);
    _pending = _PendingImport(
      _packs!.prepareImport(
        scope: scope,
        pack: preview.pack,
        source: preview.source,
        install: install,
        pinned: install ? (existing?.isPinned ?? false) : true,
        expectedRevision: existing?.revision ?? 0,
      ),
    );
    await _applyPending();
  }

  Future<void> _applyPending() async {
    final pending = _pending;
    final scope = _scope;
    if (_busy ||
        pending == null ||
        scope == null ||
        !scope.isCurrent ||
        !_visible) {
      return;
    }
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = 'กำลังบันทึกแพ็ก';
    });
    var acknowledged = false;
    try {
      final result = switch (pending) {
        _PendingImport(:final intent) => await _packs!.importPack(intent),
        _PendingCache(:final intent) => await _packs!.changeCache(intent),
      };
      if (!_resultCurrent(operation, scope)) return;
      acknowledged = true;
      setState(() {
        _pending = null;
        _status = switch (pending) {
          _PendingImport(:final intent) =>
            intent.install ? 'ติดตั้งแพ็กบทเรียนแล้ว' : 'เก็บไฟล์ออฟไลน์แล้ว',
          _PendingCache(:final intent) =>
            intent.repair != null
                ? 'ซ่อมไฟล์แพ็กแล้ว'
                : intent.pinned
                ? 'ปักหมุดไฟล์แล้ว'
                : 'เลิกปักหมุดไฟล์แล้ว',
        };
        if (pending is _PendingCache && pending.intent.remove) {
          _status = 'ลบเฉพาะไฟล์แพ็กแล้ว การ์ด สื่อ และประวัติการเรียนยังอยู่';
        }
        _view = _Detail(
          PackDetail(pack: result, content: null, bindings: const []),
        );
      });
      _notice(_status!);
      final rows = await _packs!.list(scope);
      final detail = await _packs!.detail(scope, result.id);
      if (!_resultCurrent(operation, scope)) return;
      setState(() {
        _rows = rows;
        _view = _Detail(detail);
      });
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(
          () => _status = acknowledged
              ? 'บันทึกแล้ว แต่ยังอ่านรายละเอียดไม่ได้ กดโหลดรายการใหม่ได้'
              : _failure(error),
        );
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _openStored(StoredLearningPack row) async {
    if (!_canAct) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = null;
    });
    PackOwnerScope? scope;
    try {
      scope = await _capture();
      if (scope == null || row.ownerId != scope.ownerId) return;
      final detail = await _packs!.detail(scope, row.id);
      if (!_resultCurrent(operation, scope)) return;
      setState(() {
        _scope = scope;
        _view = _Detail(detail);
      });
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _download(LearningPackDownloadDescriptor descriptor) async {
    if (!_canAct || _downloads == null) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _received = 0;
      _expected = descriptor.packageByteCount;
      _status = 'กำลังดาวน์โหลด';
    });
    PackOwnerScope? scope;
    try {
      scope = await _capture();
      if (scope == null || !_resultCurrent(operation, scope)) return;
      final active = scope;
      final pack = await _downloads!.download(
        descriptor,
        stillCurrent: () => _resultCurrent(operation, active),
        onProgress: (received, expected) {
          if (_resultCurrent(operation, active)) {
            setState(() {
              _received = received;
              _expected = expected;
            });
          }
        },
      );
      if (!_resultCurrent(operation, scope)) return;
      setState(() {
        _scope = scope;
        _view = _Preview(
          pack,
          PackSourceDescriptor.configuredCatalog(descriptor.catalogId),
        );
        _status = 'ตรวจไฟล์แล้ว เลือกติดตั้งหรือเก็บไฟล์ออฟไลน์';
      });
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) {
        setState(() {
          _busy = false;
          _received = null;
          _expected = null;
        });
      }
    }
  }

  Future<void> _cacheChange(
    StoredLearningPack pack, {
    required bool pinned,
    bool remove = false,
  }) async {
    final scope = _scope;
    if (!_canAct || scope == null || !scope.isCurrent) return;
    if (remove) {
      _overlay = true;
      bool? confirmed;
      try {
        confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ลบไฟล์แพ็กออฟไลน์?'),
            content: const Text(
              'ลบเฉพาะไฟล์แพ็กและการปักหมุด คำศัพท์ การ์ด สื่อ และประวัติการเรียนยังอยู่',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('เก็บไว้'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('ลบไฟล์แพ็ก'),
              ),
            ],
          ),
        );
      } finally {
        _overlay = false;
      }
      if (confirmed != true || !scope.isCurrent || !_visible) return;
    }
    _pending = _PendingCache(
      _packs!.prepareCacheChange(
        scope: scope,
        stored: pack,
        pinned: pinned,
        remove: remove,
      ),
    );
    await _applyPending();
  }

  Future<void> _installStored(PackDetail detail) async {
    final scope = _scope;
    final content = detail.content;
    if (!_canAct || scope == null || content == null || !scope.isCurrent) {
      return;
    }
    _pending = _PendingImport(
      _packs!.prepareImport(
        scope: scope,
        pack: content,
        source: detail.pack.source,
        pinned: detail.pack.isPinned,
        expectedRevision: detail.pack.revision,
      ),
    );
    await _applyPending();
  }

  Future<void> _openWord(PackDetail detail, PackLexicalBinding binding) async {
    final scope = _scope;
    if (!_canAct || scope == null || !scope.isCurrent) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final current = await _packs!.currentLexical(
        scope: scope,
        wordId: binding.wordId,
        packVersionId: detail.pack.id,
      );
      if (!_resultCurrent(operation, scope)) return;
      if (current == null) {
        throw const PackStorageException(PackStorageFailureCode.staleContent);
      }
      setState(() => _view = _Lexical(current, detail));
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<CurrentLexicalContent?> _freshWord(CurrentLexicalContent word) async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return null;
    return _packs!.currentLexical(
      scope: scope,
      wordId: word.word.id,
      packVersionId: word.pack.id,
    );
  }

  bool get _practiceAvailable =>
      _dependencies?.learning != null &&
      _dependencies!.features.isVisible(Feature.srs);

  bool get _definitionAvailable =>
      _dependencies?.learning != null &&
      _dependencies!.features.isVisible(Feature.quiz);

  Future<void> _startPractice(
    PackDetail shown,
    List<PackLexicalBinding> requested, {
    bool definition = false,
  }) async {
    final dependencies = _dependencies;
    final scope = _scope;
    bool available() => definition ? _definitionAvailable : _practiceAvailable;
    if (!_canAct ||
        !available() ||
        scope == null ||
        !scope.isCurrent ||
        requested.isEmpty ||
        requested.length > 20) {
      return;
    }
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _status = null;
    });
    var launched = false;
    Route<dynamic>? launchedRoute;
    try {
      final fresh = await _packs!.detail(scope, shown.pack.id);
      if (!_resultCurrent(operation, scope) || !available()) return;
      for (final selected in requested) {
        if (!fresh.bindings.any(
          (binding) =>
              binding.isCurrent &&
              binding.wordId == selected.wordId &&
              binding.wordRevision == selected.wordRevision &&
              binding.entry.canonicalJson == selected.entry.canonicalJson,
        )) {
          throw const PackStorageException(PackStorageFailureCode.staleContent);
        }
      }
      final ids = List<String>.unmodifiable(
        requested.map((binding) => binding.wordId),
      );
      if (ids.toSet().length != ids.length) {
        throw const PackStorageException(PackStorageFailureCode.invalid);
      }
      ConfiguredQuizLaunch? quizLaunch;
      if (definition) {
        _overlay = true;
        final LexicalQuizConfiguration? configuration;
        try {
          if (!mounted) return;
          configuration = await showDialog<LexicalQuizConfiguration>(
            context: context,
            builder: (_) => LexicalQuizSetupDialog(
              packVersionId: shown.pack.id,
              packTitle: shown.pack.manifest.title,
              cefrLevel: shown.pack.manifest.cefrLevel,
              entries: requested.map((binding) => binding.entry),
            ),
          );
        } finally {
          _overlay = false;
        }
        if (configuration == null ||
            !_resultCurrent(operation, scope) ||
            !_visible ||
            !available() ||
            _route?.isCurrent != true) {
          return;
        }
        quizLaunch = await dependencies!.learning!.prepareLexicalQuiz(
          expectedOwnerId: scope.ownerId,
          packVersionId: configuration.packVersionId,
          entryCodes: configuration.entryCodes,
          input: configuration.input,
          limit: configuration.limit,
          settings: configuration.settings,
          hints: configuration.hints,
          stillCurrent: () =>
              _resultCurrent(operation, scope) && _visible && available(),
        );
        if (!_resultCurrent(operation, scope) || !_visible || !available()) {
          return;
        }
      }
      if (!mounted) return;
      _stopVoice();
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.removeCurrentSnackBar();
      final ownerChanges = _packs!.watchActiveOwnerId();
      void childRouteChanged(Route<dynamic>? route, bool current) {
        if (_operationCurrent(operation) &&
            route != null &&
            identical(route, _practiceChildRoute) &&
            route.isActive &&
            !current &&
            _practiceRoute?.isCurrent != true) {
          scheduleMicrotask(() {
            if (_operationCurrent(operation)) {
              _covered = true;
              _cancelWork();
            }
          });
          return;
        }
        if (route != null && !current) return;
        if (_resultCurrent(operation, scope) &&
            identical(dependencies, _dependencies) &&
            available()) {
          _practiceChildRoute = route;
        }
      }

      launched = true;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: definition ? 'learning-packs/definition' : 'learning-packs/srs',
          reduceMotion:
              quizLaunch?.configuration.lexical?.settings.reduceMotion == true,
          builder: (_) {
            if (!_resultCurrent(operation, scope) ||
                !identical(dependencies, _dependencies) ||
                !available()) {
              return const Scaffold(
                body: Center(
                  child: Text('การฝึกไม่พร้อมใช้งาน โปรดเปิดแพ็กใหม่'),
                ),
              );
            }
            if (definition) {
              return QuizScreen(
                resultBackLabel: 'กลับแพ็กคำศัพท์',
                preparedLaunch: quizLaunch!,
                expectedOwnerId: scope.ownerId,
                ownerChanges: ownerChanges,
                onOwnedRouteChanged: childRouteChanged,
                learning: dependencies!.learning,
                learningTime: dependencies.learningTime,
                voice: _voice,
              );
            }
            return SrsFlashcardsScreen(
              sourceWordIds: ids,
              expectedOwnerId: scope.ownerId,
              ownerChanges: ownerChanges,
              learning: dependencies!.learning,
              voice: _voice,
              learningTime: dependencies.learningTime,
            );
          },
        ),
        onRouteCreated: (route) {
          launchedRoute = route;
          _practiceRoute = route;
        },
      );
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
      }
    } finally {
      if (identical(_practiceRoute, launchedRoute)) {
        _practiceChildRoute = null;
        _practiceRoute = null;
      }
      _saved?.syncVisibility();
      if (_operationCurrent(operation)) {
        setState(() => _busy = false);
        if (launched && _visible && scope.isCurrent) {
          await _openStored(shown.pack);
        }
      }
    }
  }

  Future<void> _speak(CurrentLexicalContent word) async {
    if (!_canAct || _voice == null) return;
    final operation = ++_operation;
    final scope = _scope;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final current = await _freshWord(word);
      if (!_resultCurrent(operation, scope)) return;
      if (current == null) {
        throw const PackStorageException(PackStorageFailureCode.staleContent);
      }
      _ownsPlayback = true;
      await _voice!.speak(
        VoiceRequest.create(
          text: current.word.spelling,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          contentId: 'pack:${current.pack.packageSha256}:${current.entry.code}',
          contentType: 'vocabulary_word',
          mode: VoiceMode.practice,
        ),
      );
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(
          () => _status = error is PackStorageException
              ? _failure(error)
              : 'ระบบอ่านออกเสียงยังไม่พร้อมใช้งาน',
        );
        _notice(_status!);
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _saveWord(CurrentLexicalContent word) async {
    final binding = _saved;
    if (!_canAct || binding?.ready != true) return;
    if (binding!.conflicted(word.word.id)) {
      setState(() => _status = 'สถานะคำเปลี่ยนแล้ว กดโหลดรายการใหม่ก่อนบันทึก');
      return;
    }
    final operation = ++_operation;
    final scope = _scope;
    final epoch = binding.generation;
    setState(() => _busy = true);
    try {
      final current = await _freshWord(word);
      if (!_resultCurrent(operation, scope) || !binding.isCurrent(epoch)) {
        return;
      }
      if (current == null) {
        throw const PackStorageException(PackStorageFailureCode.staleContent);
      }
      if (binding.pendingFor(current.word.id) != null) {
        await binding.retry(current.word.id, epoch);
      } else {
        await binding.setSaved(
          current.word.id,
          !(binding.stateFor(current.word.id)?.isSaved ?? false),
          epoch,
        );
      }
      if (_resultCurrent(operation, scope)) {
        setState(
          () => _status = binding.pendingFor(current.word.id) != null
              ? 'ยังยืนยันการบันทึกคำไม่ได้ ลองคำสั่งเดิมอีกครั้งได้'
              : binding.conflicted(current.word.id)
              ? 'สถานะคำเปลี่ยนแล้ว กดโหลดรายการใหม่ก่อนลองอีกครั้ง'
              : 'บันทึกสถานะคำแล้ว',
        );
      }
      if (_resultCurrent(operation, scope) && _status != null) {
        _notice(_status!);
      }
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
        _notice(_status!);
      }
    } finally {
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _reportWord(CurrentLexicalContent word) async {
    if (!_canAct || _reports == null) return;
    final operation = ++_operation;
    final scope = _scope;
    setState(() => _busy = true);
    try {
      final current = await _freshWord(word);
      if (!_resultCurrent(operation, scope) || !mounted) {
        return;
      }
      if (current == null) {
        throw const PackStorageException(PackStorageFailureCode.staleContent);
      }
      final reportOwners = _packs!.watchActiveOwnerId();
      _overlay = true;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => !_resultCurrent(operation, scope)
            ? const SizedBox.shrink()
            : WordReportSheet(
                expectedOwnerId: scope!.ownerId,
                target: WordReportTarget.fromWord(current.word),
                wordReports: _reports,
                ownerChanges: reportOwners,
              ),
      );
    } catch (error) {
      if (_resultCurrent(operation, scope)) {
        setState(() => _status = _failure(error));
        _notice(_status!);
      }
    } finally {
      _overlay = false;
      if (_operationCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _validatePackReport(CurrentLexicalContent shown) async {
    final scope = _scope;
    final view = _view;
    if (!_visible ||
        scope?.isCurrent != true ||
        view is! _Lexical ||
        !identical(view.content, shown)) {
      throw StateError('The reported entry is no longer displayed');
    }
    final fresh = await _freshWord(shown);
    if (!_visible ||
        !identical(scope, _scope) ||
        scope?.isCurrent != true ||
        !identical(view, _view) ||
        fresh == null ||
        fresh.pack.id != shown.pack.id ||
        fresh.pack.packageSha256 != shown.pack.packageSha256 ||
        fresh.entry.contentSha256 != shown.entry.contentSha256 ||
        fresh.word.localRevision != shown.word.localRevision) {
      throw StateError('The reported pack entry changed');
    }
  }

  void _stopVoice() {
    final voice = _voice;
    if (!_ownsPlayback || voice == null) return;
    _ownsPlayback = false;
    unawaited(() async {
      try {
        await voice.stop();
      } on Object {
        // Leaving a card must remain available when audio cannot stop cleanly.
      }
    }());
  }

  void _notice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _back() {
    if (_view case _Lexical(:final detail)) {
      _cancelWork();
      setState(() => _view = _Detail(detail));
      unawaited(_openStored(detail.pack));
    } else {
      _cancelWork();
      unawaited(_reload());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _wakePicker();
    if (!_foreground && !_picker) _cancelWork();
    _saved?.syncVisibility();
    if (_foreground && !_picker && !_busy && !_retired) unawaited(_reload());
  }

  @override
  void dispose() {
    _lease++;
    _operation++;
    _wakePicker();
    _stopVoice();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_owners?.cancel());
    unawaited(_saved?.close());
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _view is _Catalog,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'แพ็กบทเรียน'),
        leading: _view is _Catalog
            ? null
            : IconButton(
                tooltip: 'กลับไปยังรายการแพ็ก',
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          IconButton(
            key: const ValueKey('pack-refresh'),
            tooltip: 'โหลดรายการใหม่',
            onPressed: _visible && !_busy ? _reload : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AdaptiveContentPane(
        child: ListView(
          key: ObjectKey(_view),
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) ...[
              LinearProgressIndicator(
                value: _received != null && _expected != null && _expected! > 0
                    ? _received! / _expected!
                    : null,
                semanticsLabel: 'กำลังดำเนินการกับแพ็กบทเรียน',
              ),
              const SizedBox(height: 16),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(liveRegion: true, child: Text(_status!)),
              ),
            if (_retired || _packs == null)
              const Text('แพ็กบทเรียนยังไม่พร้อมใช้งาน')
            else
              ...switch (_view) {
                _Catalog() => _catalog(),
                _Preview(:final pack) => _preview(pack),
                _Remote(:final descriptor) => _remote(descriptor),
                _Detail(:final detail) => _detail(detail),
                _Lexical(:final content) => _lexical(content),
              },
            if (_pending != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('pack-retry'),
                onPressed: _retryAction(),
                child: const Text('ลองบันทึกคำสั่งเดิมอีกครั้ง'),
              ),
              const Text(
                'หากยังไม่แน่ใจผล กดโหลดรายการใหม่เพื่อตรวจข้อมูลที่บันทึกไว้',
              ),
            ],
          ],
        ),
      ),
    ),
  );

  List<Widget> _catalog() {
    bool matches(LearningPackManifest manifest) =>
        (_cefr == 'all' || manifest.cefrLevel == _cefr) &&
        '${manifest.title} ${manifest.provenance.author} ${manifest.objectives.join(' ')}'
            .toLowerCase()
            .contains(_search.text.trim().toLowerCase());
    final local = _rows.where((row) => matches(row.manifest)).toList();
    final remote = (_downloads?.catalog ?? <LearningPackDownloadDescriptor>[])
        .where((row) => matches(row.manifest))
        .toList();
    return [
      if (matches(bundledStarterPack.manifest)) ...[
        Text(
          'แพ็กเริ่มต้นที่มีในแอป',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            key: const ValueKey('pack-open-starter'),
            title: Text(bundledStarterPack.manifest.title),
            subtitle: Text(
              '${bundledStarterPack.manifest.cefrLevel} · เวอร์ชัน ${bundledStarterPack.manifest.version} · ${bundledStarterPack.manifest.entryCount} คำ\nเปิดตัวอย่างและเลือกติดตั้งได้โดยไม่ใช้อินเทอร์เน็ต',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _action(_openStarter),
          ),
        ),
        const SizedBox(height: 16),
      ],
      TextField(
        key: const ValueKey('pack-search'),
        controller: _search,
        decoration: const InputDecoration(
          labelText: 'ค้นหาแพ็ก',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const ValueKey('pack-cefr'),
        isExpanded: true,
        initialValue: _cefr,
        decoration: const InputDecoration(labelText: 'ระดับ CEFR'),
        items: [
          for (final value in const ['all', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
            DropdownMenuItem(
              value: value,
              child: Text(value == 'all' ? 'ทุกระดับ' : value),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _cefr = value);
        },
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const ValueKey('pack-import'),
        onPressed: _action(_importFile),
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('นำเข้าไฟล์แพ็ก'),
      ),
      const SizedBox(height: 20),
      Text('แพ็กในเครื่อง', style: Theme.of(context).textTheme.titleMedium),
      if (local.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('ยังไม่มีแพ็กในเครื่องที่ตรงกับการค้นหา'),
        ),
      for (final row in local)
        Card(
          child: ListTile(
            key: ValueKey('pack-row-${row.id}'),
            title: Text(row.manifest.title),
            subtitle: Text(
              '${row.manifest.cefrLevel} · เวอร์ชัน ${row.manifest.version}\n${_cacheLabel(row.cacheState)}${row.isPinned ? ' · ปักหมุดแล้ว' : ''}${row.identityConflict ? '\nพบหลายฉบับในเวอร์ชันเดียวกัน' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _action(() => _openStored(row)),
          ),
        ),
      if (remote.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          'แพ็กจากแหล่งที่ตั้งค่าไว้',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final descriptor in remote)
          Card(
            child: ListTile(
              title: Text(descriptor.manifest.title),
              subtitle: Text(
                '${descriptor.manifest.cefrLevel} · เวอร์ชัน ${descriptor.manifest.version}',
              ),
              trailing: const Icon(Icons.download_outlined),
              onTap: _action(() => setState(() => _view = _Remote(descriptor))),
            ),
          ),
      ],
    ];
  }

  List<Widget> _preview(LearningPack pack) => [
    ..._metadata(pack.manifest, pack.byteCount),
    const Text('ดูตัวอย่างไฟล์แล้ว ยังไม่เพิ่มคำศัพท์จนกว่าจะเลือกติดตั้ง'),
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('pack-confirm-install'),
      onPressed: _action(
        () => _installPreview(_view as _Preview, install: true),
      ),
      child: const Text('ติดตั้งและเพิ่มคำศัพท์'),
    ),
    OutlinedButton(
      key: const ValueKey('pack-cache-preview'),
      onPressed: _action(
        () => _installPreview(_view as _Preview, install: false),
      ),
      child: const Text('เก็บไฟล์ออฟไลน์ก่อน'),
    ),
    _metadataDetails(pack.manifest),
    ..._entryPreview(pack),
  ];

  List<Widget> _remote(LearningPackDownloadDescriptor descriptor) => [
    ..._metadata(descriptor.manifest, descriptor.packageByteCount),
    FilledButton.icon(
      key: const ValueKey('pack-download'),
      onPressed: _action(() => _download(descriptor)),
      icon: const Icon(Icons.download),
      label: const Text('ดาวน์โหลดเพื่อตรวจและดูตัวอย่าง'),
    ),
    _metadataDetails(descriptor.manifest),
  ];

  List<Widget> _detail(PackDetail detail) {
    final pack = detail.pack;
    final current = detail.bindings
        .where((binding) => binding.isCurrent)
        .toList();
    return [
      ..._metadata(pack.manifest, pack.packageByteCount),
      Text(_cacheLabel(pack.cacheState)),
      if (pack.identityConflict)
        const Text(
          'มีไฟล์ต่างกันในเวอร์ชันเดียวกัน โปรดตรวจคำศัพท์ของฉบับนี้ก่อนใช้',
        ),
      if (!pack.isInstalled && detail.content != null)
        FilledButton(
          key: const ValueKey('pack-install-cached'),
          onPressed: _action(() => _installStored(detail)),
          child: const Text('เพิ่มคำศัพท์จากแพ็ก'),
        ),
      if (pack.cacheState == PackCacheState.verified)
        OutlinedButton.icon(
          key: const ValueKey('pack-pin'),
          onPressed: _action(() => _cacheChange(pack, pinned: !pack.isPinned)),
          icon: Icon(pack.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
          label: Text(pack.isPinned ? 'เลิกปักหมุดไฟล์' : 'ปักหมุดไฟล์ออฟไลน์'),
        ),
      OutlinedButton.icon(
        key: const ValueKey('pack-repair'),
        onPressed: _action(() => _importFile(repair: pack)),
        icon: const Icon(Icons.build_outlined),
        label: const Text('ซ่อมจากไฟล์แพ็กเดิม'),
      ),
      if (pack.cacheState != PackCacheState.notCached)
        TextButton.icon(
          key: const ValueKey('pack-remove'),
          onPressed: _action(
            () => _cacheChange(pack, pinned: false, remove: true),
          ),
          icon: const Icon(Icons.delete_outline),
          label: const Text('ลบเฉพาะไฟล์แพ็กออฟไลน์'),
        ),
      _metadataDetails(pack.manifest),
      const SizedBox(height: 16),
      if (pack.isInstalled) ...[
        if (_definitionAvailable &&
            current.any((binding) => binding.entry.definition != null)) ...[
          const Text('ฝึกจากนิยามที่มีอยู่ในแพ็ก'),
          for (var offset = 0; offset < current.length; offset += 20)
            if (current
                .skip(offset)
                .take(20)
                .any((binding) => binding.entry.definition != null))
              OutlinedButton.icon(
                key: ValueKey('pack-definition-${offset ~/ 20}'),
                onPressed: _action(
                  () => _startPractice(
                    detail,
                    current.skip(offset).take(20).toList(),
                    definition: true,
                  ),
                ),
                icon: const Icon(Icons.quiz_outlined),
                label: Text('ฝึกนิยามชุดที่ ${offset ~/ 20 + 1}'),
              ),
        ],
        if (_practiceAvailable && current.isNotEmpty) ...[
          const Text('ฝึกเฉพาะคำที่ยังตรงกับเนื้อหานี้ ชุดละไม่เกิน 20 คำ'),
          for (var offset = 0; offset < current.length; offset += 20)
            FilledButton.icon(
              key: ValueKey('pack-practice-${offset ~/ 20}'),
              onPressed: _action(
                () => _startPractice(
                  detail,
                  current.skip(offset).take(20).toList(),
                ),
              ),
              icon: const Icon(Icons.style_outlined),
              label: Text(
                'ทบทวนชุดที่ ${offset ~/ 20 + 1} (${current.skip(offset).take(20).length} คำ)',
              ),
            ),
        ],
        Text('คำศัพท์ในแพ็ก', style: Theme.of(context).textTheme.titleMedium),
        for (final binding in detail.bindings)
          Card(
            child: ListTile(
              key: ValueKey('pack-word-${binding.entry.code}'),
              title: Text(binding.entry.spelling),
              subtitle: Text(
                binding.isCurrent
                    ? binding.entry.meaning
                    : 'คำเปลี่ยนแล้ว เก็บข้อมูลเดิมไว้เป็นประวัติ',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: binding.isCurrent
                  ? _action(() => _openWord(detail, binding))
                  : null,
            ),
          ),
      ] else if (detail.content != null)
        ..._entryPreview(detail.content!),
    ];
  }

  List<Widget> _metadata(LearningPackManifest manifest, int bytes) => [
    Text(manifest.title, style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    Text(
      '${manifest.cefrLevel} · เวอร์ชัน ${manifest.version} · ${manifest.entryCount} คำ · ${_size(bytes)}',
    ),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'เนื้อหาของแพ็กนี้ยังไม่ได้รับการรับรองจากผู้เชี่ยวชาญ การตรวจไฟล์ยืนยันความครบถ้วนของไฟล์เท่านั้น',
      ),
    ),
  ];

  Widget _metadataDetails(LearningPackManifest manifest) => ExpansionTile(
    key: const ValueKey('pack-metadata-details'),
    title: const Text('รายละเอียดแพ็ก'),
    childrenPadding: const EdgeInsets.all(16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('เป้าหมาย', style: Theme.of(context).textTheme.titleMedium),
      for (final objective in manifest.objectives) Text('• $objective'),
      const SizedBox(height: 16),
      Text('ผู้จัดทำ: ${manifest.provenance.author}'),
      Text('แหล่งที่มา: ${manifest.provenance.source}'),
      Text('สิทธิ์ใช้งานที่ผู้จัดทำระบุ: ${manifest.provenance.license}'),
      Text(manifest.provenance.attribution),
    ],
  );

  List<Widget> _entryPreview(LearningPack pack) => [
    const SizedBox(height: 16),
    Text('ตัวอย่างคำศัพท์', style: Theme.of(context).textTheme.titleMedium),
    for (final entry in pack.entries)
      ListTile(title: Text(entry.spelling), subtitle: Text(entry.meaning)),
  ];

  List<Widget> _lexical(CurrentLexicalContent content) {
    final entry = content.entry;
    final saved = _saved;
    return [
      Text(entry.spelling, style: Theme.of(context).textTheme.headlineMedium),
      Text(entry.partOfSpeech, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 12),
      Text(entry.meaning),
      RichLexicalCard(
        content: content,
        showAssistance: true,
        showIdentity: false,
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_definitionAvailable && entry.definition != null)
            OutlinedButton.icon(
              key: const ValueKey('pack-word-definition'),
              onPressed: _action(
                () => _startPractice((_view as _Lexical).detail, [
                  content.binding,
                ], definition: true),
              ),
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('ฝึกจากนิยาม'),
            ),
          if (_practiceAvailable)
            FilledButton.icon(
              key: const ValueKey('pack-word-practice'),
              onPressed: _action(
                () => _startPractice((_view as _Lexical).detail, [
                  content.binding,
                ]),
              ),
              icon: const Icon(Icons.style_outlined),
              label: const Text('ฝึกคำนี้'),
            ),
          if (_voice != null)
            FilledButton.tonalIcon(
              key: const ValueKey('pack-word-speak'),
              onPressed: _action(() => _speak(content)),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('ฟังคำ'),
            ),
          if (saved != null)
            OutlinedButton.icon(
              key: const ValueKey('pack-word-save'),
              onPressed: saved.ready ? _action(() => _saveWord(content)) : null,
              icon: Icon(
                saved.stateFor(content.word.id)?.isSaved == true
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              label: Text(
                saved.pendingFor(content.word.id) != null
                    ? 'ลองบันทึกคำเดิมอีกครั้ง'
                    : saved.stateFor(content.word.id)?.isSaved == true
                    ? 'นำออกจากคำที่บันทึก'
                    : 'บันทึกคำ',
              ),
            ),
          if (_reports != null)
            OutlinedButton.icon(
              key: const ValueKey('pack-word-report'),
              onPressed: _action(() => _reportWord(content)),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('รายงานคำ'),
            ),
          if (_scope != null)
            ContentReportButton.content(
              key: const ValueKey('content-report-pack-entry'),
              expectedOwnerId: _scope!.ownerId,
              sourceIdentity: (
                content.pack.id,
                content.pack.packageSha256,
                entry.contentSha256,
                content.word.localRevision,
              ),
              sourceText: contentReportEntryText(entry),
              callerContext: LearningTimeCallerContext.ordinary,
              canOpen: () =>
                  _canAct &&
                  _scope?.isCurrent == true &&
                  _view is _Lexical &&
                  identical((_view as _Lexical).content, content),
              beforeOpen: () => _validatePackReport(content),
              revalidateSource: (_) => _validatePackReport(content),
              onOverlayChanged: (open) {
                _overlay = open;
              },
              targetForSelection: (text, excerpt) =>
                  ContentReportTarget.packEntry(
                    text: text,
                    isExcerpt: excerpt,
                    packId: content.pack.manifest.packId,
                    packVersion: content.pack.manifest.version,
                    packageSha256: content.pack.packageSha256,
                    entryCode: entry.code,
                    entrySha256: entry.contentSha256,
                  ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        'จาก ${content.pack.manifest.title} · เวอร์ชัน ${content.pack.manifest.version}',
      ),
      Text('ผู้จัดทำ: ${content.pack.manifest.provenance.author}'),
      const Text('เนื้อหายังไม่ได้รับการรับรองจากผู้เชี่ยวชาญ'),
    ];
  }
}

sealed class _PackView {
  const _PackView();
}

final class _Catalog extends _PackView {
  const _Catalog();
}

final class _Preview extends _PackView {
  const _Preview(this.pack, this.source);
  final LearningPack pack;
  final PackSourceDescriptor source;
}

final class _Remote extends _PackView {
  const _Remote(this.descriptor);
  final LearningPackDownloadDescriptor descriptor;
}

final class _Detail extends _PackView {
  const _Detail(this.detail);
  final PackDetail detail;
}

final class _Lexical extends _PackView {
  const _Lexical(this.content, this.detail);
  final CurrentLexicalContent content;
  final PackDetail detail;
}

sealed class _PendingPackWrite {
  const _PendingPackWrite();
}

final class _PendingImport extends _PendingPackWrite {
  const _PendingImport(this.intent);
  final PackImportIntent intent;
}

final class _PendingCache extends _PendingPackWrite {
  const _PendingCache(this.intent);
  final PackCacheIntent intent;
}

Future<XFile?> _pickFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'แพ็กบทเรียน JSON',
      extensions: ['json', 'lqpack'],
      mimeTypes: ['application/json'],
    ),
  ],
);
LearningPack _decodePack(Uint8List bytes) =>
    const LearningPackCodec().decode(bytes);
String _size(int bytes) => bytes < 1024
    ? '$bytes ไบต์'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
String _cacheLabel(PackCacheState state) => switch (state) {
  PackCacheState.notCached => 'ยังไม่มีไฟล์ออฟไลน์',
  PackCacheState.cached => 'มีไฟล์ในเครื่อง ยังไม่ได้ตรวจ',
  PackCacheState.verified => 'ตรวจไฟล์ในเครื่องแล้ว',
  PackCacheState.corrupt => 'ไฟล์ในเครื่องเสียหาย ซ่อมจากไฟล์เดิมได้',
};
String _failure(Object error) => switch (error) {
  PackStorageException(:final code) => switch (code) {
    PackStorageFailureCode.ownerChanged =>
      'ผู้เรียนหรือพื้นที่ข้อมูลเปลี่ยนแล้ว โปรดเปิดรายการใหม่',
    PackStorageFailureCode.conflict =>
      'ข้อมูลแพ็กเปลี่ยนหรือมีไฟล์ต่างกันในเวอร์ชันเดียวกัน โปรดโหลดรายการใหม่',
    PackStorageFailureCode.notFound => 'ไม่พบแพ็กนี้แล้ว โปรดโหลดรายการใหม่',
    PackStorageFailureCode.staleContent =>
      'คำศัพท์เปลี่ยนแล้ว ไม่ใช้คำอธิบายเดิมกับการฝึกใหม่',
    PackStorageFailureCode.corrupt =>
      'ข้อมูลแพ็กไม่ครบหรือเสียหาย ซ่อมจากไฟล์เดิมได้',
    PackStorageFailureCode.invalid => 'ไฟล์หรือคำสั่งไม่ตรงกับแพ็กที่เลือก',
    PackStorageFailureCode.unavailable =>
      'ยังยืนยันผลไม่ได้ ลองคำสั่งเดิมอีกครั้งหรือโหลดรายการใหม่',
  },
  LearningPackException(:final code) => switch (code) {
    LearningPackFailureCode.tooLarge =>
      'ไฟล์แพ็กหรือรูปมีขนาดเกินขอบเขตที่รองรับ',
    LearningPackFailureCode.integrityMismatch =>
      'ไฟล์ไม่ตรงกับแพ็กเดิม โปรดเลือกไฟล์ฉบับที่ถูกต้อง',
    _ => 'ไฟล์นี้ไม่ใช่แพ็กบทเรียนที่รองรับ หรือข้อมูลไม่ครบ',
  },
  _ => 'ยังดำเนินการกับแพ็กไม่ได้ ลองใหม่ได้โดยไม่เปลี่ยนประวัติการเรียน',
};
