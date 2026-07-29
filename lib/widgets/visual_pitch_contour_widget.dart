import 'package:flutter/material.dart';

/// Renders reference TTS pitch contour vs user spoken pitch contour (Chiang 2019, Sitti 2022).
class VisualPitchContourWidget extends StatelessWidget {
  const VisualPitchContourWidget({
    super.key,
    required this.referencePitchPoints,
    required this.userPitchPoints,
    this.height = 100,
  });

  final List<double> referencePitchPoints;
  final List<double> userPitchPoints;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        size: Size(double.infinity, height - 24),
        painter: _PitchContourPainter(
          referencePoints: referencePitchPoints,
          userPoints: userPitchPoints,
        ),
      ),
    );
  }
}

class _PitchContourPainter extends CustomPainter {
  const _PitchContourPainter({
    required this.referencePoints,
    required this.userPoints,
  });

  final List<double> referencePoints;
  final List<double> userPoints;

  @override
  void paint(Canvas canvas, Size size) {
    if (referencePoints.isEmpty) return;

    final refPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final userPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawPoints(canvas, size, referencePoints, refPaint);
    if (userPoints.isNotEmpty) {
      _drawPoints(canvas, size, userPoints, userPaint);
    }
  }

  void _drawPoints(Canvas canvas, Size size, List<double> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path();
    final stepX = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height * (1.0 - points[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PitchContourPainter oldDelegate) {
    return oldDelegate.referencePoints != referencePoints ||
        oldDelegate.userPoints != userPoints;
  }
}
