import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../application/learner_intent_use_cases.dart';
import '../domain/learner_intent.dart';

/// Local intent actions only; no correctness, reward or mastery writer.
final class BookmarkLearningItemButton extends StatefulWidget {
  const BookmarkLearningItemButton({
    super.key,
    required this.identity,
    required this.onSave,
  });
  final ContentIdentity identity;
  final BookmarkLearningItemAction onSave;
  @override
  State<BookmarkLearningItemButton> createState() =>
      _BookmarkLearningItemButtonState();
}

final class _BookmarkLearningItemButtonState
    extends State<BookmarkLearningItemButton> {
  bool _pending = false;
  String? _message;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant BookmarkLearningItemButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.onSave != widget.onSave) {
      _generation++;
      _pending = false;
      _message = null;
    }
  }

  Future<void> _run(
    BookmarkLearningItemAction action, {
    required bool removing,
  }) async {
    if (_pending) return;
    final generation = _generation;
    final identity = widget.identity;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await action(identity);
      if (!mounted || generation != _generation) return;
      setState(
        () => _message = removing
            ? 'นำออกจากรายการในเครื่องแล้ว'
            : 'บันทึกไว้ในเครื่องแล้ว',
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _message = removing
            ? 'นำออกไม่สำเร็จ ลองอีกครั้ง'
            : 'บันทึกไม่สำเร็จ ลองอีกครั้ง',
      );
    } finally {
      if (mounted && generation == _generation) {
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
