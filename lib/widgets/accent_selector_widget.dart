import 'package:flutter/material.dart';

enum VoiceAccent {
  us('US', 'อเมริกัน 🇺🇸', 'teacher_female_us'),
  uk('UK', 'อังกฤษ 🇬🇧', 'teacher_female_uk'),
  au('AU', 'ออสเตรเลีย 🇦🇺', 'teacher_female_au');

  final String code;
  final String label;
  final String voiceId;

  const VoiceAccent(this.code, this.label, this.voiceId);
}

class AccentSelectorWidget extends StatelessWidget {
  final VoiceAccent selectedAccent;
  final ValueChanged<VoiceAccent> onAccentChanged;

  const AccentSelectorWidget({
    super.key,
    required this.selectedAccent,
    required this.onAccentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'เลือกสำเนียงเสียงอ่าน AI OmniVoice:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: VoiceAccent.values.map((accent) {
            final isSelected = accent == selectedAccent;
            return ChoiceChip(
              label: Text(accent.label),
              selected: isSelected,
              selectedColor: Colors.deepPurple.shade100,
              onSelected: (selected) {
                if (selected) onAccentChanged(accent);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
