import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/review_ladder.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'srs_flashcards_screen.dart';
import 'weakness_clinic_screen.dart';

typedef _ReviewSubmission = ({
  ReviewLadderRound expected,
  ReviewLadderAction action,
  DateTime atUtc,
  int? option,
  String? text,
});

class ReviewDeskScreen extends StatefulWidget {
  const ReviewDeskScreen({
    super.key,
    required this.learning,
    required this.expectedOwnerId,
  });

  final LearningUseCases learning;
  final String expectedOwnerId;

  static bool available(AppDependencies? scope) =>
      scope != null &&
      scope.learning?.supportsReviewLadder == true &&
      _visible(scope, Feature.vocabulary, FieldFeature.vocabulary) &&
      _visible(scope, Feature.srs, FieldFeature.srs);

  static bool _visible(
    AppDependencies scope,
    Feature feature,
    FieldFeature fieldFeature,
  ) =>
      scope.features.isVisible(feature) &&
      scope.fieldFeatures.isVisible(fieldFeature);

  @override
  State<ReviewDeskScreen> createState() => _ReviewDeskScreenState();
}

class _ReviewDeskScreenState extends State<ReviewDeskScreen> {
  final _typedAnswer = TextEditingController();
  final _ownerFence = ValueNotifier(true);
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _ownerChanges;
  StreamSubscription<void>? _ownerWrites;
  Future<ReviewDeskData>? _desk;
  ReviewLadderRound? _round;
  _ReviewSubmission? _pending;
  bool _invalidated = false;
  bool _busy = false;
  bool _showCard = false;
  bool _finished = false;
  String? _error;

  bool get _current => mounted && !_invalidated;
  bool get _ready => _current && !_busy && _pending == null;
  bool get _canPractice {
    final scope = _dependencies;
    return scope != null &&
        ReviewDeskScreen.available(scope) &&
        ReviewDeskScreen._visible(scope, Feature.quiz, FieldFeature.quiz);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppDependenciesScope.maybeOf(context);
    if (_desk != null) {
      if (!identical(scope, _dependencies)) _invalidated = true;
      return;
    }
    if (scope == null || !identical(scope.learning, widget.learning)) {
      _invalidated = true;
      return;
    }
    _dependencies = scope;
    _ownerChanges = scope.watchActiveOwnerId()?.listen((ownerId) {
      if (ownerId != widget.expectedOwnerId) _invalidate();
    }, onError: (Object _) => _invalidate());
    _ownerWrites = scope.watchLocalOwnerWrites()?.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
    _loadDesk();
  }

  @override
  void didUpdateWidget(covariant ReviewDeskScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.learning, widget.learning) ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId) {
      _invalidated = true;
    }
  }

  @override
  void dispose() {
    unawaited(_ownerChanges?.cancel());
    unawaited(_ownerWrites?.cancel());
    _ownerFence.dispose();
    _typedAnswer.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (!_current) return;
    setState(() => _invalidated = true);
    _ownerFence.value = false;
  }

  void _loadDesk() {
    final load = widget.learning.loadReviewDesk(
      expectedOwnerId: widget.expectedOwnerId,
    );
    load.ignore();
    _desk = load;
  }

  Future<void> _open(ReviewLadderPair pair) async {
    if (!_ready || !_canPractice) return;
    await _run(() async {
      final round = await widget.learning.openReviewLadder(
        expectedOwnerId: widget.expectedOwnerId,
        pair: pair,
      );
      if (!_current) return;
      _round = round;
      await _finishIfReady();
    });
  }

  void _openHistory(ReviewLadderRound round) {
    if (!_ready) return;
    setState(() {
      _round = round;
      _finished = true;
      _error = null;
    });
  }

  Future<void> _openActivity(String name, Widget page) async {
    if (!_ready) return;
    await _run(() async {
      final ownerId = await _dependencies?.readActiveOwnerId();
      if (!mounted || _invalidated || ownerId != widget.expectedOwnerId) {
        _invalidate();
        return;
      }
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: name,
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: _ownerFence,
            builder: (context, valid, child) =>
                valid &&
                    _current &&
                    identical(
                      AppDependenciesScope.maybeOf(context),
                      _dependencies,
                    )
                ? child!
                : Scaffold(appBar: AppBar(), body: _contextChangedMessage),
            child: page,
          ),
        ),
      );
      if (_current) _loadDesk();
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on Object {
      if (_current) _error = 'บันทึกรอบทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง';
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  void _returnToDesk() {
    if (!_current || _busy) return;
    setState(() {
      _round = null;
      _pending = null;
      _showCard = false;
      _finished = false;
      _error = null;
      _typedAnswer.clear();
      _loadDesk();
    });
  }

  Future<void> _submit(ReviewLadderAction action, {int? option}) async {
    final round = _round;
    if (!_ready || !_canPractice || round == null) return;
    String? text;
    if (action == ReviewLadderAction.checkTyped) {
      text = _typedAnswer.text;
      try {
        normalizeQuizClozeAnswer(text);
      } on FormatException {
        setState(() => _error = 'พิมพ์คำตอบก่อนกดตรวจ');
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _pending = (
      expected: round,
      action: action,
      atUtc: widget.learning.nowUtc(),
      option: option,
      text: text,
    );
    await _retry();
  }

  Future<void> _retry() async {
    if (!_current || !_canPractice || _busy) return;
    await _run(() async {
      if (_pending case final request?) {
        final saved = await widget.learning.changeReviewLadder(
          expectedOwnerId: widget.expectedOwnerId,
          expected: request.expected,
          action: request.action,
          atUtc: request.atUtc,
          option: request.option,
          text: request.text,
        );
        if (!_current) return;
        _round = saved;
        _pending = null;
        _showCard = request.action == ReviewLadderAction.revealCard;
      }
      await _finishIfReady();
    });
  }

  Future<void> _finishIfReady() async {
    final round = _round;
    if (round != null &&
        round.phase == ReviewLadderPhase.result &&
        !_finished) {
      await widget.learning.finishReviewLadder(
        expectedOwnerId: widget.expectedOwnerId,
        round: round,
      );
      if (_current) _finished = true;
    }
  }

  void _closeCard() => setState(() => _showCard = false);

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return PopScope<void>(
      canPop: _invalidated || (round == null && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_current || _busy || round == null) return;
        if (_showCard) {
          _closeCard();
        } else {
          _returnToDesk();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(
            context,
            _invalidated || round == null
                ? 'เลือกสิ่งที่จะทบทวน'
                : _showCard
                ? 'บัตรคำที่ช่วยนึก'
                : _phaseTitle(round),
          ),
        ),
        bottomNavigationBar:
            !_invalidated &&
                round?.phase == ReviewLadderPhase.result &&
                _finished
            ? SafeArea(
                top: false,
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AdaptiveContentPane.formMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: _button(
                          'กลับไปเลือกสิ่งที่จะทบทวน',
                          _ready ? _returnToDesk : null,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: SafeArea(
            child: _invalidated
                ? _contextChangedMessage
                : round == null
                ? FutureBuilder<ReviewDeskData>(
                    future: _desk,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _list([
                          const Text('เปิดศูนย์ทบทวนไม่สำเร็จ'),
                          TextButton(
                            onPressed: () => setState(_loadDesk),
                            child: const Text('ลองอีกครั้ง'),
                          ),
                        ]);
                      }
                      return snapshot.hasData
                          ? _deskContent(snapshot.requireData)
                          : const Center(child: CircularProgressIndicator());
                    },
                  )
                : _roundContent(round),
          ),
        ),
      ),
    );
  }

  Widget _deskContent(ReviewDeskData data) {
    final scope = _dependencies!;
    return _list([
      if (ReviewDeskScreen.available(scope))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.style_outlined),
          title: const Text('ฝึกด้วยบัตรคำ'),
          onTap: _ready
              ? () => _openActivity(
                  'learning/review-due',
                  SrsFlashcardsScreen(expectedOwnerId: widget.expectedOwnerId),
                )
              : null,
        ),
      if (ReviewDeskScreen._visible(
            scope,
            Feature.weakness,
            FieldFeature.weakness,
          ) &&
          scope.progress != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history_outlined),
          title: const Text('คำที่ยังสับสน'),
          onTap: _ready
              ? () => _openActivity(
                  'learning/review-weakness',
                  WeaknessClinicScreen(expectedOwnerId: widget.expectedOwnerId),
                )
              : null,
        ),
      if (_canPractice)
        if (data.pair case final pair?)
          _button('ฝึกให้จำได้ด้วยตัวเอง', _ready ? () => _open(pair) : null)
        else
          const Text('ทบทวนคำด้วยบัตรคำก่อนเพื่อเริ่มฝึกให้นึกคำได้เอง'),
      if (data.latest case final round?)
        OutlinedButton(
          onPressed: _ready ? () => _openHistory(round) : null,
          child: const Text('ดูผลรอบล่าสุด'),
        ),
    ]);
  }

  String _phaseTitle(ReviewLadderRound round) => switch (round.phase) {
    ReviewLadderPhase.intro => 'ฝึกให้นึกคำได้เอง',
    ReviewLadderPhase.meaning => 'เลือกความหมาย',
    ReviewLadderPhase.compare => 'ลองเทียบสองคำนี้',
    ReviewLadderPhase.advance => 'เลือกความหมายได้แล้ว',
    ReviewLadderPhase.typed => 'นึกคำที่หายไป',
    ReviewLadderPhase.result =>
      !_finished
          ? 'บันทึกผลการทบทวน'
          : round.typedCorrect
          ? 'พิมพ์คำได้ถูกต้อง'
          : 'ผลการฝึกทบทวน',
  };

  Widget _roundContent(ReviewLadderRound round) {
    final pair = round.pair;
    if (_showCard) {
      return _list([
        Text(pair.categoryName),
        _prompt('${pair.target.spelling} · ${pair.target.meaning}'),
        const Text(ReviewLadderRound.completedSentence),
        _button('กลับไปฝึกต่อ', _ready ? _closeCard : null),
      ]);
    }
    return _list([
      Text(pair.categoryName),
      ...switch (round.phase) {
        ReviewLadderPhase.intro => [
          _prompt(pair.target.spelling),
          const Text('เริ่มจากคำที่เคยทบทวน'),
          _action('ลองเลือกความหมาย', ReviewLadderAction.startMeaning),
          _action(
            'ดูบัตรคำก่อน',
            ReviewLadderAction.revealCard,
            secondary: true,
          ),
          _button('กลับไปเลือกสิ่งที่จะทบทวน', _ready ? _returnToDesk : null),
        ],
        ReviewLadderPhase.meaning => [
          _prompt(pair.target.spelling),
          const Text('คำนี้หมายถึงอะไร'),
          _action(
            pair.contrast.meaning,
            ReviewLadderAction.checkMeaning,
            option: 0,
            secondary: true,
          ),
          _action(
            pair.target.meaning,
            ReviewLadderAction.checkMeaning,
            option: 1,
            secondary: true,
          ),
        ],
        ReviewLadderPhase.compare => [
          _prompt('ชานชาลาเป็นส่วนหนึ่งของสถานี'),
          Text('${pair.target.spelling} · ${pair.target.meaning}'),
          Text('${pair.contrast.spelling} · ${pair.contrast.meaning}'),
          _action('ลองเลือกความหมายอีกครั้ง', ReviewLadderAction.retryMeaning),
          _action(
            'ดูบัตรคำก่อน',
            ReviewLadderAction.revealCard,
            secondary: true,
          ),
        ],
        ReviewLadderPhase.advance => [
          _prompt('${pair.target.spelling} · ${pair.target.meaning}'),
          const Text('ขั้นต่อไปจะเห็นประโยคกับคำแปล'),
          _action('ลองนึกคำโดยไม่มีตัวเลือก', ReviewLadderAction.startTyping),
          _action(
            'ทบทวนขั้นเดิม',
            ReviewLadderAction.retryMeaning,
            secondary: true,
          ),
        ],
        ReviewLadderPhase.typed => [
          _prompt(ReviewLadderRound.typedPrompt),
          const Text(ReviewLadderRound.typedTranslation),
          TextField(
            key: const ValueKey('review-ladder-typed'),
            controller: _typedAnswer,
            readOnly: !_ready,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'คำที่นึกได้'),
          ),
          _action('ตรวจคำตอบ', ReviewLadderAction.checkTyped),
          _action('ขอคำใบ้', ReviewLadderAction.revealCard, secondary: true),
        ],
        ReviewLadderPhase.result => _finished ? _result(round) : [],
      },
    ]);
  }

  List<Widget> _result(ReviewLadderRound round) {
    final first = round.independentChoice;
    final typed = round.typedCheck!;
    return [
      _prompt('คุณเลือกความหมายได้ก่อนนึกคำจากประโยค'),
      if (first != null)
        Text('คะแนนการเลือกครั้งแรก ${first.option == 1 ? 1 : 0}/1')
      else
        const Text('การเลือกครั้งแรกใช้บัตรคำ'),
      for (final check in round.meaningChecks)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            check.assisted
                ? 'เลือกความหมายหลังดูคำช่วย'
                : 'เลือกความหมายครั้งแรก',
          ),
          subtitle: Text(
            check.option == 1
                ? '${round.pair.target.meaning} · ถูก'
                : '${round.pair.contrast.meaning} · ผิด',
          ),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          typed.assisted ? 'พิมพ์หลังดูคำใบ้' : 'พิมพ์จากประโยคหลังทบทวน',
        ),
        subtitle: Text('${typed.text} · ${round.typedCorrect ? "ถูก" : "ผิด"}'),
      ),
      const Text(ReviewLadderRound.completedSentence),
    ];
  }

  Widget _list(List<Widget> content) => ListView(
    key: ValueKey((_round?.phase, _showCard)),
    padding: const EdgeInsets.all(24),
    children: [
      if (_busy) const LinearProgressIndicator(semanticsLabel: 'กำลังบันทึก'),
      if (_error case final error?)
        Semantics(liveRegion: true, child: Text(error)),
      if (_error != null &&
          (_pending != null ||
              (_round?.phase == ReviewLadderPhase.result && !_finished)))
        _button('ลองบันทึกอีกครั้ง', _busy || !_canPractice ? null : _retry),
      for (final child in content) ...[child, const SizedBox(height: 12)],
    ],
  );

  Widget _prompt(String text) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);

  Widget _button(String label, VoidCallback? press) =>
      FilledButton(onPressed: press, child: Text(label));

  Widget _action(
    String label,
    ReviewLadderAction action, {
    int? option,
    bool secondary = false,
  }) {
    final press = _ready && _canPractice
        ? () => _submit(action, option: option)
        : null;
    return secondary
        ? OutlinedButton(onPressed: press, child: Text(label))
        : _button(label, press);
  }
}

const _contextChangedMessage = Center(
  child: Padding(
    padding: EdgeInsets.all(24),
    child: Text('กรุณากลับไปเปิดศูนย์ทบทวนอีกครั้ง'),
  ),
);
