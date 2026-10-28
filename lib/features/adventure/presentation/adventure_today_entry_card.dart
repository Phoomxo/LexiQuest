import 'package:flutter/material.dart';

import '../../../navigation/navigation_glossary.dart';

final class AdventureTodayEntryCard extends StatefulWidget {
  const AdventureTodayEntryCard({super.key, required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  State<AdventureTodayEntryCard> createState() =>
      _AdventureTodayEntryCardState();
}

final class _AdventureTodayEntryCardState
    extends State<AdventureTodayEntryCard> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = NavigationGlossary.require('home/learn/today-experience');
    return Card(
      key: const ValueKey('home/learn/today-experience'),
      child: InkWell(
        onTap: _opening ? null : _open,
        borderRadius: BorderRadius.circular(16),
        child: Semantics(
          button: true,
          enabled: !_opening,
          label: entry.semanticsLabel,
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Icon(entry.icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.fullThaiLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'เปลี่ยนรายการวันนี้เป็นเส้นทางภารกิจแบบเบา ๆ',
                        ),
                      ],
                    ),
                  ),
                  if (_opening)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
