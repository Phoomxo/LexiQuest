import 'package:flutter/material.dart';
import '../learning/association_record.dart';

class AssociationDialogWidget extends StatefulWidget {
  final String wordKey;
  final List<AssociationRecord> prompts;
  final Function(AssociationRecord)? onSelect;
  final Function(CueType type, String text)? onCreate;

  const AssociationDialogWidget({
    super.key,
    required this.wordKey,
    required this.prompts,
    this.onSelect,
    this.onCreate,
  });

  @override
  State<AssociationDialogWidget> createState() =>
      _AssociationDialogWidgetState();
}

class _AssociationDialogWidgetState extends State<AssociationDialogWidget> {
  final TextEditingController _customController = TextEditingController();
  CueType _selectedType = CueType.personalStory;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Memory Cue for "${widget.wordKey}"'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select a memory prompt or write your own private association:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (widget.prompts.isNotEmpty) ...[
              const Text(
                'Suggested Cues:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...widget.prompts.map(
                (p) => ListTile(
                  dense: true,
                  title: Text(p.cueText),
                  subtitle: Text('${p.cueType.name} • ${p.source.name}'),
                  trailing: const Icon(Icons.check_circle_outline),
                  onTap: () {
                    widget.onSelect?.call(p);
                    Navigator.of(context).pop(p);
                  },
                ),
              ),
              const Divider(),
            ],
            const Text(
              'Create Custom Cue:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            DropdownButton<CueType>(
              value: _selectedType,
              isExpanded: true,
              items: CueType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),
            TextField(
              controller: _customController,
              decoration: const InputDecoration(
                hintText: 'Enter your personal story or visual cue...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = _customController.text.trim();
            if (text.isNotEmpty) {
              widget.onCreate?.call(_selectedType, text);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save Cue'),
        ),
      ],
    );
  }
}
