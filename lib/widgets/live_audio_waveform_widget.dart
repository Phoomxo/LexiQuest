import 'package:flutter/material.dart';

/// Real-Time Live Audio Waveform Spectrum Visualizer Widget.
class LiveAudioWaveformWidget extends StatelessWidget {
  const LiveAudioWaveformWidget({
    super.key,
    required this.audioLevels,
    this.height = 80,
    this.barColor = Colors.cyanAccent,
  });

  final List<double> audioLevels; // 0.0 to 1.0
  final double height;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: barColor.withOpacity(0.4)),
      ),
      child: CustomPaint(
        size: Size(double.infinity, height - 16),
        painter: _WaveformPainter(levels: audioLevels, color: barColor),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    final stepX = size.width / (levels.length > 1 ? levels.length : 1);
    final centerY = size.height / 2;

    for (int i = 0; i < levels.length; i++) {
      final x = i * stepX + stepX / 2;
      final barHeight = (size.height * levels[i].clamp(0.1, 1.0)) / 2;
      canvas.drawLine(
        Offset(x, centerY - barHeight),
        Offset(x, centerY + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.levels != levels || oldDelegate.color != color;
  }
}
