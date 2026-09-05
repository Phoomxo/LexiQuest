import 'dart:async';

import 'package:flutter/material.dart';

import '../application/adventure_research_runtime.dart';
import '../domain/motivation_measurement.dart';
import '../domain/research_participation_permit.dart';
import 'research_participation_panel.dart';

/// Enrollment imports issuer authority; local UI never creates it.
class ResearchParticipationScreen extends StatefulWidget {
  const ResearchParticipationScreen({
    super.key,
    required this.runtime,
    required this.ownerId,
  });
  final AdventureResearchRuntime runtime;
  final String ownerId;
  @override
  State<ResearchParticipationScreen> createState() =>
      _ResearchParticipationScreenState();
}

class _ResearchParticipationScreenState
    extends State<ResearchParticipationScreen>
    with WidgetsBindingObserver {
  late Future<ResearchParticipationPermit?> _permit;
  StreamSubscription<void>? _changes;
  Timer? _expiry;
  int _contextGeneration = 0;
  int _readGeneration = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _bindContext();
  }

  @override
  void didUpdateWidget(covariant ResearchParticipationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime) ||
        oldWidget.ownerId != widget.ownerId) {
      _contextGeneration++;
      unawaited(_changes?.cancel());
      _bindContext();
    }
  }

  void _bindContext() {
    final generation = _contextGeneration;
    unawaited(_refresh(rebuild: false));
    _changes = widget.runtime.useCases
        .watch(widget.ownerId)
        .listen(
          (_) {
            if (mounted && generation == _contextGeneration) {
              unawaited(_refresh());
            }
          },
          onError: (Object _, StackTrace _) {
            if (mounted && generation == _contextGeneration) _hidePermit();
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_refresh());
    } else {
      _hidePermit();
    }
  }

  void _hidePermit() {
    _readGeneration++;
    _expiry?.cancel();
    setState(() {
      _permit = Future<ResearchParticipationPermit?>.value(null);
    });
  }

  Future<void> _refresh({bool rebuild = true}) {
    _expiry?.cancel();
    final read = ++_readGeneration;
    final runtime = widget.runtime;
    final owner = widget.ownerId;
    final contextGeneration = _contextGeneration;
    final future = _foreground
        ? _loadPermit(runtime, owner, contextGeneration, read)
        : Future<ResearchParticipationPermit?>.value(null);
    // The closure must not return the assigned Future: setState is synchronous.
    if (rebuild) {
      setState(() {
        _permit = future;
      });
    } else {
      _permit = future;
    }
    return future.then<void>((_) {});
  }

  Future<ResearchParticipationPermit?> _loadPermit(
    AdventureResearchRuntime runtime,
    String owner,
    int contextGeneration,
    int read,
  ) async {
    try {
      final permit = await runtime.currentPermit(owner);
      if (!_isCurrent(runtime, owner, contextGeneration) ||
          read != _readGeneration ||
          !_foreground ||
          permit == null) {
        return null;
      }
      // Authority can take time. Never publish a result already expired by the
      // time it arrives, even if it was valid when the runtime began its read.
      final remaining = permit.expiresAtUtc.difference(
        runtime.participation.nowUtc(),
      );
      if (remaining <= Duration.zero) return null;
      _expiry = Timer(remaining, () {
        if (_isCurrent(runtime, owner, contextGeneration) &&
            read == _readGeneration) {
          unawaited(_refresh());
        }
      });
      return permit;
    } on Object {
      // Unavailable authority is not verified participation. No raw errors,
      // receipts or documents are rendered or logged by this projection.
      return null;
    }
  }

  bool _isCurrent(
    AdventureResearchRuntime runtime,
    String owner,
    int generation,
  ) =>
      mounted &&
      generation == _contextGeneration &&
      identical(runtime, widget.runtime) &&
      owner == widget.ownerId;

  void _requireCurrent(
    AdventureResearchRuntime runtime,
    String owner,
    int generation,
  ) {
    if (!_isCurrent(runtime, owner, generation)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.ownerConflict);
    }
  }

  Future<void> _import(
    AdventureResearchRuntime runtime,
    String owner,
    int generation,
    String document,
  ) async {
    _requireCurrent(runtime, owner, generation);
    await runtime.importDocument(owner, document);
    _requireCurrent(runtime, owner, generation);
    await _refresh();
  }

  Future<void> _withdraw(
    AdventureResearchRuntime runtime,
    String owner,
    int generation,
  ) async {
    _requireCurrent(runtime, owner, generation);
    await runtime.withdraw(owner);
    _requireCurrent(runtime, owner, generation);
    _hidePermit();
  }

  @override
  void dispose() {
    _contextGeneration++;
    _readGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final runtime = widget.runtime;
    final owner = widget.ownerId;
    final generation = _contextGeneration;
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Research participation' : 'การเข้าร่วมวิจัย'),
      ),
      body: FutureBuilder<ResearchParticipationPermit?>(
        future: _permit,
        builder: (context, snapshot) => ResearchParticipationPanel(
          // Replacing an owner/runtime also disposes any opaque pasted input,
          // including when both old and new permit projections are null.
          key: ValueKey(generation),
          permit:
              snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError
              ? snapshot.data
              : null,
          languageCode: english ? 'en' : 'th',
          onImport: (document) => _import(runtime, owner, generation, document),
          onWithdraw: () => _withdraw(runtime, owner, generation),
          onContinueLearning: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
