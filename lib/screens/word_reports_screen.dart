import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/word_report_use_cases.dart';
import '../features/vocabulary/domain/word_report.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import '../widgets/word_report_sheet.dart';

class WordReportsScreen extends StatefulWidget {
  const WordReportsScreen({
    super.key,
    required this.expectedOwnerId,
    this.wordReports,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final String expectedOwnerId;
  final WordReportUseCases? wordReports;
  final Stream<String?>? ownerChanges;
  final String languageCode;
  @override
  State<WordReportsScreen> createState() => _WordReportsScreenState();
}

class _WordReportsScreenState extends State<WordReportsScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  WordReportUseCases? _reports;
  WordReportOwnerScope? _scope;
  StreamSubscription<List<StoredWordReport>>? _rows;
  List<StoredWordReport>? _snapshot;
  ModalRoute<dynamic>? _route;
  bool _bound = false;
  bool _foreground = false;
  bool _paneVisible = false;
  bool _invalidated = false;
  bool _readFailed = false;
  int _scopeEpoch = -1;
  int _readToken = 0;
  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _visible =>
      mounted &&
      !_invalidated &&
      _foreground &&
      _paneVisible &&
      _route?.isCurrent == true;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _paneVisible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final reports = widget.wordReports ?? dependencies?.wordReports;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _reports = reports;
      final owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (reports != null && owners != null) {
        _scope = WordReportOwnerScope(
          ownerChanges: owners,
          visible: () => _visible,
          expectedOwnerId: widget.expectedOwnerId,
        )..addListener(_scopeChanged);
      }
    } else if (!identical(dependencies, _dependencies) ||
        !identical(reports, _reports)) {
      _invalidate();
    }
    _scope?.synchronize();
  }

  @override
  void didUpdateWidget(covariant WordReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.wordReports, widget.wordReports) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidate();
    }
  }

  void _invalidate() {
    _invalidated = true;
    _clearRows();
    _scope?.invalidate();
  }

  void _clearRows() {
    _readToken++;
    final rows = _rows;
    _rows = null;
    unawaited(rows?.cancel());
    _snapshot = null;
    _readFailed = false;
  }

  void _scopeChanged() {
    final scope = _scope;
    if (scope?.current != true) {
      _clearRows();
    } else if (scope!.generation != _scopeEpoch) {
      _scopeEpoch = scope.generation;
      _clearRows();
      _watch();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _watch() {
    final scope = _scope;
    final reports = _reports;
    if (scope == null || !scope.current || reports == null) {
      return;
    }
    final epoch = scope.generation;
    final token = ++_readToken;
    bool current() =>
        mounted &&
        !_invalidated &&
        scope.isCurrent(epoch) &&
        token == _readToken;
    _rows = reports
        .watchOwner(widget.expectedOwnerId)
        .listen(
          (rows) {
            if (!current()) {
              return;
            }
            if (rows.any((row) => row.ownerId != widget.expectedOwnerId)) {
              _invalidate();
              return;
            }
            setState(() {
              _snapshot = List<StoredWordReport>.unmodifiable(rows);
              _readFailed = false;
            });
          },
          onError: (Object _, StackTrace _) {
            if (current()) {
              setState(() {
                _snapshot = null;
                _readFailed = true;
              });
            }
          },
          onDone: () {
            if (current()) {
              setState(() {
                _rows = null;
                _snapshot = null;
                _readFailed = true;
              });
            }
          },
        );
  }

  void _retry() {
    if (_scope?.current != true) {
      return;
    }
    _clearRows();
    _watch();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scope?.synchronize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _invalidated = true;
    WidgetsBinding.instance.removeObserver(this);
    _clearRows();
    _scope?.removeListener(_scopeChanged);
    unawaited(_scope?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    Widget body;
    if (_invalidated ||
        scope == null ||
        scope.blocked ||
        !scope.current && scope.observed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _text(
              'รายการรายงานไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่',
              'Report history is unavailable. Go back and open it again.',
            ),
          ),
        ),
      );
    } else if (_readFailed) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _text(
                'อ่านรายงานในเครื่องไม่สำเร็จ',
                'Could not load local reports.',
              ),
            ),
            OutlinedButton(
              key: const ValueKey('word-reports-read-retry'),
              onPressed: _retry,
              child: Text(_text('ลองใหม่', 'Retry')),
            ),
          ],
        ),
      );
    } else if (!scope.current || _snapshot == null) {
      body = const Center(
        child: CircularProgressIndicator(key: ValueKey('word-reports-loading')),
      );
    } else if (_snapshot!.isEmpty) {
      body = Center(
        child: Text(
          _text('ยังไม่มีรายงานในเครื่อง', 'No local reports yet.'),
          key: const ValueKey('word-reports-empty'),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _text(
              'รายการนี้เก็บในเครื่อง ยังไม่ได้ส่ง',
              'These reports are stored on this device. Not sent.',
            ),
          ),
          const SizedBox(height: 12),
          for (final report in _snapshot!)
            Card(
              child: ExpansionTile(
                key: ValueKey('word-report-history-row:${report.id}'),
                title: Text(report.target.spelling),
                subtitle: Text(
                  wordReportReasonLabel(report.reason, widget.languageCode),
                ),
                childrenPadding: const EdgeInsets.all(16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WordReportDetails(
                    report: report,
                    languageCode: widget.languageCode,
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(
          context,
          _text('รายงานในเครื่อง', 'Local reports'),
        ),
      ),
      body: AdaptiveContentPane(child: body),
    );
  }
}
