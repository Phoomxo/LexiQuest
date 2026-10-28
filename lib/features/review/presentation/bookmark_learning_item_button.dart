import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../application/learner_intent_use_cases.dart';
import '../domain/learner_intent.dart';
import '../domain/review_mutation_context.dart';
import 'review_mutation_state.dart';

/// Local intent actions only; no correctness, reward or mastery writer.
final class BookmarkLearningItemButton extends StatefulWidget {
  const BookmarkLearningItemButton({
    super.key,
    required this.identity,
    required this.onSave,
    this.canInteract,
    this.validateAction,
    this.expectedOwnerId,
  });
  final ContentIdentity identity;
  final BookmarkLearningItemAction onSave;
  final bool Function()? canInteract;
  final Future<void> Function()? validateAction;
  final String? expectedOwnerId;
  @override
  State<BookmarkLearningItemButton> createState() =>
      _BookmarkLearningItemButtonState();
}

final class _BookmarkLearningItemButtonState
    extends ReviewMutationState<BookmarkLearningItemButton> {
  bool _pending = false;
  String? _message;
  Object? _repository;

  @override
  void retireMutation() {
    super.retireMutation();
    _pending = false;
    _message = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = AppDependenciesScope.maybeOf(context)?.learnerIntents;
    if (!identical(repository, _repository)) retireMutation();
    _repository = repository;
  }

  @override
  void didUpdateWidget(covariant BookmarkLearningItemButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.onSave != widget.onSave ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId) {
      retireMutation();
    }
  }

  Future<void> _run(
    BookmarkLearningItemAction action, {
    required bool removing,
  }) async {
    if (!mutationVisible || _pending || widget.canInteract?.call() == false)
      return;
    final generation = mutationGeneration;
    final identity = widget.identity;
    final canInteract = widget.canInteract;
    final validate = widget.validateAction;
    final expectedOwnerId = widget.expectedOwnerId;
    bool current() =>
        mutationCurrent(generation) && canInteract?.call() != false;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await validate?.call();
      if (!current()) return;
      await ReviewMutationContext.run(
        () => action(identity),
        isCurrent: current,
        expectedOwnerId: expectedOwnerId,
      );
      await validate?.call();
      if (!current()) return;
      setState(
        () => _message = removing
            ? 'นำออกจากรายการในเครื่องแล้ว'
            : 'บันทึกไว้ในเครื่องแล้ว',
      );
    } catch (_) {
      if (!current()) return;
      setState(
        () => _message = removing
            ? 'ยังยืนยันการนำออกไม่ได้ ลองอีกครั้ง'
            : 'ยังยืนยันการบันทึกไม่ได้ ลองอีกครั้ง',
      );
    } finally {
      if (mounted && generation == mutationGeneration) {
        setState(() => _pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = AppDependenciesScope.maybeOf(context)?.learnerIntents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          button: true,
          label: 'บันทึกไว้ทบทวน',
          enabled: !_pending,
          onTap: _pending ? null : () => _run(widget.onSave, removing: false),
          child: ExcludeSemantics(
            child: OutlinedButton.icon(
              onPressed: _pending
                  ? null
                  : () => _run(widget.onSave, removing: false),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('บันทึกไว้ทบทวน'),
            ),
          ),
        ),
        if (repository != null)
          TextButton.icon(
            onPressed: _pending
                ? null
                : () => _run(
                    UnsaveLearningItemUseCase(repository).call,
                    removing: true,
                  ),
            icon: const Icon(Icons.bookmark_remove_outlined),
            label: const Text('นำออกจากรายการที่บันทึก'),
          ),
        if (_pending || _message != null)
          Semantics(
            liveRegion: true,
            child: Text(_pending ? 'กำลังบันทึก…' : _message!),
          ),
      ],
    );
  }
}
