import 'package:flutter/material.dart';
import '../application/managed_tutor_controller.dart';

/// Reusable view only; the host supplies and disposes the controller. No login
/// action is offered until a supported provider route exists.
class ManagedTutorPanel extends StatefulWidget {
  const ManagedTutorPanel({super.key, required this.controller});
  final ManagedTutorController controller;
  @override
  State<ManagedTutorPanel> createState() => _ManagedTutorPanelState();
}

class _ManagedTutorPanelState extends State<ManagedTutorPanel> {
  final _draft = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ManagedTutorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _draft.clear();
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (widget.controller.state != ManagedTutorState.ready) _draft.clear();
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final busy =
        state == ManagedTutorState.pending ||
        state == ManagedTutorState.replying;
    final ready = state == ManagedTutorState.ready;
    final label = switch (state) {
      ManagedTutorState.disconnected => 'ยังไม่ได้เชื่อมต่อ',
      ManagedTutorState.pending => 'กำลังเตรียมการเชื่อมต่อ',
      ManagedTutorState.ready => 'พร้อมสนทนา',
      ManagedTutorState.replying => 'อารีกำลังตอบ',
      ManagedTutorState.cancelled => 'ยกเลิกแล้ว',
      ManagedTutorState.expired => 'การเชื่อมต่อหรือคำขอหมดเวลา',
      ManagedTutorState.offline => 'ออฟไลน์ กรุณาตรวจการเชื่อมต่อ',
      ManagedTutorState.quotaExhausted => 'โควตาหมด กรุณารอรอบถัดไป',
      ManagedTutorState.providerUnavailable => 'อารียังไม่พร้อมให้บริการ',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('อารี', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(label)),
        if (busy) const LinearProgressIndicator(),
        if (controller.replyText case final String reply) ...[
          const SizedBox(height: 12),
          SelectableText(reply),
        ],
        if (ready) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _draft,
            maxLength: 4000,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'ข้อความถึงอารี'),
          ),
        ],
        Wrap(
          spacing: 8,
          children: [
            if (ready)
              FilledButton(
                onPressed: () => controller.send(_draft.text),
                child: const Text('ส่ง'),
              ),
            if (busy)
              TextButton(
                onPressed: controller.cancel,
                child: const Text('ยกเลิก'),
              ),
            if (ready || busy)
              TextButton(
                onPressed: controller.disconnect,
                child: const Text('ตัดการเชื่อมต่อ'),
              ),
          ],
        ),
      ],
    );
  }
}
