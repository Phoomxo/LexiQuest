import 'package:flutter/material.dart';

/// Renders an interactive Lexical Chunk / Collocation Mind Map Tree (Cambridge Core 2020).
class CefrCollocationTreeWidget extends StatelessWidget {
  const CefrCollocationTreeWidget({
    super.key,
    required this.rootWord,
    required this.cefrLevel,
    required this.collocations,
  });

  final String rootWord;
  final String cefrLevel;
  final List<String> collocations;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    cefrLevel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: _levelColor(cefrLevel),
                ),
                const SizedBox(width: 8),
                Text(
                  rootWord,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            const Text(
              'คำประสมภาษาอังกฤษ (Collocations):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: collocations.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'A1':
      case 'A2':
        return Colors.green;
      case 'B1':
      case 'B2':
        return Colors.orange;
      case 'C1':
      case 'C2':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}
