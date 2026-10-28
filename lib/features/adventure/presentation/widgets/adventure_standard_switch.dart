import 'package:flutter/material.dart';

import '../../domain/adventure_entry.dart';

final class AdventureStandardSwitch extends StatelessWidget {
  const AdventureStandardSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TodayExperiencePresentation value;
  final ValueChanged<TodayExperiencePresentation>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'เลือกรูปแบบกิจกรรมวันนี้',
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<TodayExperiencePresentation>(
        key: const ValueKey('adventure-standard-switch'),
        showSelectedIcon: true,
        segments: const <ButtonSegment<TodayExperiencePresentation>>[
          ButtonSegment<TodayExperiencePresentation>(
            value: TodayExperiencePresentation.standard,
            icon: Icon(Icons.view_agenda_outlined),
            label: Text('มาตรฐาน'),
          ),
          ButtonSegment<TodayExperiencePresentation>(
            value: TodayExperiencePresentation.adventure,
            icon: Icon(Icons.explore_outlined),
            label: Text('ผจญภัย'),
          ),
        ],
        selected: <TodayExperiencePresentation>{value},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) {
                if (selection.isNotEmpty) onChanged!(selection.single);
              },
      ),
    ),
  );
}
