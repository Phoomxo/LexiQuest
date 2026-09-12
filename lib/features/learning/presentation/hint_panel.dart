import 'package:flutter/material.dart';

import '../domain/hint_policy.dart';

final class HintPanel extends StatelessWidget {
  const HintPanel({
    super.key,
    required this.state,
    required this.onRevealNext,
    this.enabled = true,
  });

  final HintState state;
  final VoidCallback onRevealNext;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final buttonLabel = switch (state.availability) {
      HintAvailability.unavailable => 'ไม่มีคำใบ้สำหรับข้อนี้',
      HintAvailability.unknown => 'ตรวจสถานะคำใบ้ไม่ได้',
      HintAvailability.available when state.isExhausted => 'ใช้คำใบ้ครบแล้ว',
      HintAvailability.available when state.hintLevel == 0 => 'ดูวิธีคิด',
      HintAvailability.available => 'ดูบริบทเพิ่ม',
    };
    final canReveal =
        enabled &&
        state.availability == HintAvailability.available &&
        !state.isExhausted;

    return Semantics(
      container: true,
      liveRegion: state.revealedHints.isNotEmpty,
      label: 'คำใบ้ระดับ ${state.hintLevel} $buttonLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final hint in state.revealedHints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(hint.content),
            ),
          FilledButton(
            onPressed: canReveal ? onRevealNext : null,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
