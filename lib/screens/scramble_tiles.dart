import 'package:flutter/material.dart';

class ScrambleTiles extends StatelessWidget {
  ScrambleTiles({
    super.key,
    required List<String> tokens,
    required List<int> order,
    required this.isSentence,
    this.onChanged,
    this.onCheck,
  }) : assert(order.every((index) => index >= 0 && index < tokens.length)),
       assert(order.toSet().length == order.length),
       tokens = List.unmodifiable(tokens),
       order = List.unmodifiable(order);

  final List<String> tokens;
  final List<int> order;
  final bool isSentence;
  final ValueChanged<List<int>>? onChanged;
  final VoidCallback? onCheck;

  void _change(Iterable<int> indices) {
    onChanged?.call(List.unmodifiable(indices));
  }

  @override
  Widget build(BuildContext context) {
    final selected = order.toSet();
    final canEdit = onChanged != null;
    final canUndo = canEdit && order.isNotEmpty;
    final complete = tokens.isNotEmpty && order.length == tokens.length;
    final theme = Theme.of(context);
    final tileStyle = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      disabledForegroundColor: theme.colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    final optionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      disabledForegroundColor: theme.colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    final unit = isSentence ? 'คำ' : 'ตัวอักษร';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$unitที่เรียงไว้', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (order.isEmpty)
          Text('เลือก$unitจากด้านล่าง')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (position, index) in order.indexed)
                FilledButton.tonal(
                  key: ValueKey('scramble-selected-$index'),
                  style: tileStyle,
                  onPressed: canEdit
                      ? () => _change(order.where((chosen) => chosen != index))
                      : null,
                  child: Text(
                    tokens[index],
                    semanticsLabel: canEdit
                        ? 'เอา$unit ${tokens[index]} ลำดับที่ ${position + 1} ออก'
                        : '$unit ${tokens[index]} ลำดับที่ ${position + 1}',
                  ),
                ),
            ],
          ),
        if (!complete) ...[
          const SizedBox(height: 16),
          Text('$unitที่เหลือ', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, token) in tokens.indexed)
                if (!selected.contains(index))
                  OutlinedButton(
                    key: ValueKey('scramble-token-$index'),
                    style: optionStyle,
                    onPressed: canEdit
                        ? () => _change([...order, index])
                        : null,
                    child: Text(
                      token,
                      semanticsLabel: 'เลือก$unit $token ชิ้นที่ ${index + 1}',
                    ),
                  ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: complete && canEdit ? onCheck : null,
              child: const Text('ตรวจคำตอบ'),
            ),
            OutlinedButton(
              onPressed: canUndo
                  ? () => _change(order.take(order.length - 1))
                  : null,
              child: Text(isSentence ? 'เอาคำล่าสุดออก' : 'เอาตัวล่าสุดออก'),
            ),
            TextButton(
              onPressed: canUndo ? () => _change(const []) : null,
              child: const Text('เริ่มใหม่'),
            ),
          ],
        ),
      ],
    );
  }
}
