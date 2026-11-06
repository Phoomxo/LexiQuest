import 'package:flutter/material.dart';

import '../../../widgets/adaptive_content_pane.dart';
import '../domain/learning_timezone.dart';

typedef LearningTimezoneSelection = ({String? timezoneId});

class LearningTimezonePicker extends StatefulWidget {
  const LearningTimezonePicker({
    super.key,
    required this.selected,
    required this.stillCurrent,
    this.includeDefault = false,
  });

  final String? selected;
  final bool Function() stillCurrent;
  final bool includeDefault;

  @override
  State<LearningTimezonePicker> createState() => _LearningTimezonePickerState();
}

class _LearningTimezonePickerState extends State<LearningTimezonePicker> {
  late final _zones = <String?>[
    if (widget.includeDefault) null,
    ...learningTimezoneIds,
  ];
  var _query = '';

  String _label(String? zone) => zone ?? 'UTC (ค่าเริ่มต้น)';

  @override
  Widget build(BuildContext context) {
    final matches = _query.isEmpty
        ? _zones
        : _zones
              .where(
                (zone) =>
                    _label(
                      zone,
                    ).toLowerCase().replaceAll('_', ' ').contains(_query) ||
                    (zone == 'Asia/Bangkok' &&
                        'กรุงเทพมหานคร'.contains(_query)),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(key: Key('learning-timezone-cancel')),
        title: const Text('เลือกเขตเวลา'),
      ),
      body: SafeArea(
        child: AdaptiveContentPane(
          maxWidth: AdaptiveContentPane.formMaxWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  key: const Key('learning-timezone-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'ค้นหาเมืองหรือเขตเวลา',
                  ),
                  onChanged: (value) => setState(() {
                    _query = value.trim().toLowerCase().replaceAll('_', ' ');
                  }),
                ),
              ),
              Expanded(
                child: matches.isEmpty
                    ? const Center(child: Text('ไม่พบเขตเวลาที่ค้นหา'))
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (_, index) {
                          final zone = matches[index];
                          return ListTile(
                            title: Text(_label(zone)),
                            subtitle: zone == 'Asia/Bangkok'
                                ? const Text('กรุงเทพมหานคร')
                                : null,
                            selected: zone == widget.selected,
                            onTap: () {
                              if (mounted &&
                                  widget.stillCurrent() &&
                                  ModalRoute.of(context)?.isCurrent == true) {
                                Navigator.of(
                                  context,
                                ).pop<LearningTimezoneSelection>((
                                  timezoneId: zone,
                                ));
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
