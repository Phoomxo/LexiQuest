import 'package:flutter/material.dart';

/// Local, static artwork for the small set of reward cosmetics that have a
/// reviewed visual treatment. Unknown catalog entries deliberately show the
/// base avatar so durable reward data never becomes a rendering failure.
class RewardAvatarPreview extends StatelessWidget {
  const RewardAvatarPreview({
    super.key,
    required this.catalogVersion,
    this.itemId,
    this.size = 160,
  });

  final int catalogVersion;
  final String? itemId;
  final double size;

  static bool supports({required int catalogVersion, required String itemId}) {
    return (catalogVersion == 1 || catalogVersion == 2) &&
        itemId == 'headgear_ipa';
  }

  @override
  Widget build(BuildContext context) {
    final requestedItem = itemId?.trim();
    final showHeadgear =
        requestedItem != null &&
        supports(catalogVersion: catalogVersion, itemId: requestedItem);
    final hasUnsupportedItem = requestedItem != null && !showHeadgear;
    final resolvedKey = showHeadgear ? 'headgear_ipa' : 'base';
    final semanticsLabel = showHeadgear
        ? 'ตัวละครนักสำรวจสวมหมวก IPA'
        : hasUnsupportedItem
        ? 'ตัวละครนักสำรวจ ภาพอุปกรณ์นี้ยังไม่พร้อม'
        : 'ตัวละครนักสำรวจ';

    return Semantics(
      key: ValueKey('reward-avatar-preview/$resolvedKey'),
      label: semanticsLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RewardAvatarPainter(showHeadgear: showHeadgear),
          ),
        ),
      ),
    );
  }
}

class _RewardAvatarPainter extends CustomPainter {
  const _RewardAvatarPainter({required this.showHeadgear});

  final bool showHeadgear;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 160;
    canvas.save();
    canvas.translate((size.width - 160 * scale) / 2, 0);
    canvas.scale(scale);

    final paint = Paint()..isAntiAlias = true;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(80, 144), width: 96, height: 14),
      paint..color = const Color(0xFFBED2EB),
    );
    canvas.drawPath(
      Path()
        ..moveTo(43, 131)
        ..quadraticBezierTo(44, 96, 80, 95)
        ..quadraticBezierTo(116, 96, 117, 131)
        ..close(),
      paint..color = const Color(0xFF547BBB),
    );
    canvas.drawPath(
      Path()
        ..moveTo(71, 105)
        ..lineTo(80, 117)
        ..lineTo(89, 105),
      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(80, 68), width: 74, height: 80),
      paint..color = const Color(0xFFF7CAAA),
    );
    canvas.drawPath(
      Path()
        ..moveTo(43, 65)
        ..quadraticBezierTo(38, 27, 77, 25)
        ..quadraticBezierTo(119, 24, 118, 67)
        ..lineTo(109, 57)
        ..lineTo(104, 41)
        ..quadraticBezierTo(86, 55, 53, 49)
        ..lineTo(50, 68)
        ..close(),
      paint..color = const Color(0xFF263E60),
    );
    canvas.drawCircle(const Offset(67, 71), 3.5, paint);
    canvas.drawCircle(const Offset(94, 71), 3.5, paint);
    canvas.drawPath(
      Path()
        ..moveTo(71, 87)
        ..quadraticBezierTo(80, 94, 90, 86),
      paint
        ..color = const Color(0xFF804F3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    paint.style = PaintingStyle.fill;

    if (showHeadgear) {
      canvas.drawPath(
        Path()
          ..moveTo(43, 43)
          ..quadraticBezierTo(42, 12, 79, 12)
          ..quadraticBezierTo(110, 12, 117, 43)
          ..close(),
        paint..color = const Color(0xFF3E62A9),
      );
      canvas.drawPath(
        Path()
          ..moveTo(34, 45)
          ..quadraticBezierTo(75, 32, 126, 46)
          ..lineTo(126, 54)
          ..quadraticBezierTo(77, 44, 34, 54)
          ..close(),
        paint..color = const Color(0xFF183D75),
      );
      canvas.drawCircle(
        const Offset(81, 28),
        10,
        paint..color = const Color(0xFFF3D18A),
      );
      canvas.drawPath(
        Path()
          ..moveTo(76, 28)
          ..lineTo(80, 32)
          ..lineTo(86, 24),
        paint
          ..color = const Color(0xFF183D75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      paint.style = PaintingStyle.fill;
    }

    canvas.drawPath(
      Path()
        ..moveTo(56, 128)
        ..lineTo(71, 125)
        ..lineTo(79, 131)
        ..lineTo(87, 125)
        ..lineTo(104, 128)
        ..lineTo(104, 142)
        ..lineTo(87, 139)
        ..lineTo(79, 145)
        ..lineTo(71, 139)
        ..lineTo(56, 142)
        ..close(),
      paint
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(56, 128)
        ..lineTo(71, 125)
        ..lineTo(79, 131)
        ..lineTo(87, 125)
        ..lineTo(104, 128)
        ..lineTo(104, 142)
        ..lineTo(87, 139)
        ..lineTo(79, 145)
        ..lineTo(71, 139)
        ..lineTo(56, 142)
        ..close(),
      paint
        ..color = const Color(0xFF263E60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RewardAvatarPainter oldDelegate) {
    return oldDelegate.showHeadgear != showHeadgear;
  }
}
