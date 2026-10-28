import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A local 24-hour clock choice. Only confirmation returns an edited time.
Future<TimeOfDay?> showStudyTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required String helpText,
  ValueChanged<Route<dynamic>>? onPickerRoute,
}) {
  // The Material input picker reserves a horizontal clock row plus dialog
  // padding. Use stacked fields before that minimum can clip a narrow route.
  final needsStackedFields =
      MediaQuery.sizeOf(context).width < 360 ||
      MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3;
  if (!needsStackedFields) {
    return showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: initialTime,
      helpText: helpText,
      hourLabelText: 'ชั่วโมง',
      minuteLabelText: 'นาที',
      errorInvalidText: 'กรุณากรอกเวลาให้ถูกต้อง',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
      builder: (context, child) {
        final route = ModalRoute.of(context);
        if (route != null) onPickerRoute?.call(route);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }
  return showDialog<TimeOfDay>(
    context: context,
    builder: (context) {
      final route = ModalRoute.of(context);
      if (route != null) onPickerRoute?.call(route);
      return _StudyTimePickerDialog(
        initialTime: initialTime,
        helpText: helpText,
      );
    },
  );
}

class _StudyTimePickerDialog extends StatefulWidget {
  const _StudyTimePickerDialog({
    required this.initialTime,
    required this.helpText,
  });

  final TimeOfDay initialTime;
  final String helpText;

  @override
  State<_StudyTimePickerDialog> createState() => _StudyTimePickerDialogState();
}

class _StudyTimePickerDialogState extends State<_StudyTimePickerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hour;
  late final TextEditingController _minute;

  @override
  void initState() {
    super.initState();
    _hour = TextEditingController(
      text: widget.initialTime.hour.toString().padLeft(2, '0'),
    );
    _minute = TextEditingController(
      text: widget.initialTime.minute.toString().padLeft(2, '0'),
    );
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TimeOfDay(hour: int.parse(_hour.text), minute: int.parse(_minute.text)),
    );
  }

  String? _validate(String? value, int maximum, String message) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 0 || number > maximum ? message : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    actionsOverflowButtonSpacing: 12,
    title: Text(widget.helpText),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _hour,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'ชั่วโมง',
              helperText: '0–23',
              errorMaxLines: 3,
            ),
            validator: (value) => _validate(value, 23, 'กรอกชั่วโมง 0–23'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _minute,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'นาที',
              helperText: '0–59',
              errorMaxLines: 3,
            ),
            validator: (value) => _validate(value, 59, 'กรอกนาที 0–59'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: _confirm,
        child: const Text('ตกลง'),
      ),
    ],
  );

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }
}
