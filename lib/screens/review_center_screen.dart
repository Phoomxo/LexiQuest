import 'package:flutter/material.dart';

import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/review/application/review_center_use_cases.dart';
import '../features/review/domain/content_quality_report.dart';
import '../features/review/domain/review_queue_item.dart';
import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';

typedef ReviewLessonShellBuilder =
    UnifiedLessonShellLease Function(ReviewQueueItem item);

/// G1 f22 surface. f42 remains the sole future production parent.
final class ReviewCenterScreen extends StatefulWidget {
  const ReviewCenterScreen({
    super.key,
    required this.useCases,
    required this.lessonShellBuilder,
  });

  final ReviewCenterUseCases useCases;
  final ReviewLessonShellBuilder lessonShellBuilder;

  @override
  State<ReviewCenterScreen> createState() => _ReviewCenterScreenState();
}

final class _ReviewCenterScreenState extends State<ReviewCenterScreen> {
  late Future<List<ReviewQueueItem>> _load;
  String? _openingIdentity;

  @override
  void initState() {
    super.initState();
    _load = widget.useCases.load();
  }

  void _retry() {
    final next = widget.useCases.load();
    setState(() {
      _load = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NavigationGlossary.require('home/today/review').fullThaiLabel,
        ),
      ),
      body: FutureBuilder<List<ReviewQueueItem>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ReviewMessage(
              semanticsLabel: 'โหลดรายการทบทวนไม่สำเร็จ',
              message: 'ไม่สามารถโหลดรายการทบทวนได้',
              action: FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
              child: Semantics(
                label: 'กำลังโหลดรายการทบทวน',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const _ReviewMessage(
              semanticsLabel: 'รายการทบทวนว่าง',
              message: 'ยังไม่มีรายการที่ต้องทบทวน',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final identity = _identityKey(item);
              return _ReviewItemCard(
                item: item,
                opening: _openingIdentity == identity,
                onLaunch: _openingIdentity == null ? () => _launch(item) : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _launch(ReviewQueueItem item) async {
    if (_openingIdentity != null) return;
    final identity = _identityKey(item);
    setState(() => _openingIdentity = identity);
    UnifiedLessonShellLease? destination;
    ReviewLessonLaunchRequest? request;
    var destinationOwnsSession = false;
    var launchFailed = false;
    try {
      request = await widget.useCases.launch(item);
      destination = widget.lessonShellBuilder(request.item);
      if (!destination.usesLearningAuthority(
        widget.useCases.sessionAuthorityIdentity,
      )) {
        throw StateError(
          'review destination uses a different learning authority',
        );
      }
      destinationOwnsSession = true;
      await destination.attach(
        request.session,
        ownerId: request.ownerId,
        expectedContent: request.items,
      );
      if (!mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'home/today/review/session',
          builder: (_) => destination!.shell,
        ),
      );
    } catch (_) {
      launchFailed = true;
      if (request != null && !destinationOwnsSession) {
        try {
          await widget.useCases.abandonLaunch(request);
        } catch (_) {
          launchFailed = true;
        }
      }
    } finally {
      try {
        await destination?.retire();
      } catch (_) {
        launchFailed = true;
      }
      if (launchFailed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเริ่มการทบทวนได้')),
        );
      }
      if (mounted) setState(() => _openingIdentity = null);
    }
  }
}

final class _ReviewItemCard extends StatelessWidget {
  const _ReviewItemCard({
    required this.item,
    required this.opening,
    required this.onLaunch,
  });

  final ReviewQueueItem item;
  final bool opening;
  final VoidCallback? onLaunch;

  @override
  Widget build(BuildContext context) {
    final reasonLabels = item.provenance.map(_reasonLabel).toSet().join(', ');
    return Semantics(
      container: true,
      label: '${item.spelling}, ${item.meaning}, $reasonLabels',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.spelling,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(item.meaning),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: item.provenance
                    .toSetBy(_reasonLabel)
                    .map(_reasonChip)
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onLaunch,
                icon: opening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(opening ? 'กำลังเริ่มทบทวน' : 'เริ่มทบทวน'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonChip(ReviewReasonProvenance source) {
    final presentation = _reasonPresentation(source);
    return Chip(
      avatar: Icon(presentation.icon, size: 18),
      label: Text(presentation.label),
    );
  }
}

final class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.semanticsLabel,
    required this.message,
    this.action,
  });

  final String semanticsLabel;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

({IconData icon, String label}) _reasonPresentation(
  ReviewReasonProvenance source,
) => switch (source.reason) {
  ReviewQueueReason.dueSrs => (icon: Icons.event_repeat, label: 'ถึงกำหนด SRS'),
  ReviewQueueReason.incorrectAnswer => (
    icon: Icons.error_outline,
    label: 'เคยตอบผิด',
  ),
  ReviewQueueReason.reported => (
    icon: Icons.flag_outlined,
    label: 'รายงานไว้: ${_reportReasonLabel(source.reportReason!)}',
  ),
  ReviewQueueReason.saved => (icon: Icons.bookmark_outline, label: 'บันทึกไว้'),
};

String _reasonLabel(ReviewReasonProvenance source) =>
    _reasonPresentation(source).label;

String _reportReasonLabel(ContentReportReason reason) => switch (reason) {
  ContentReportReason.text => 'ข้อความ',
  ContentReportReason.audio => 'เสียง',
  ContentReportReason.answer => 'คำตอบ',
  ContentReportReason.explanation => 'คำอธิบาย',
};

String _identityKey(ReviewQueueItem item) =>
    '${item.identity.type.name}:${item.identity.id}@${item.identity.revision}';

extension _UniqueBy<T> on Iterable<T> {
  Iterable<T> toSetBy(Object Function(T value) keyOf) sync* {
    final keys = <Object>{};
    for (final value in this) {
      if (keys.add(keyOf(value))) yield value;
    }
  }
}
