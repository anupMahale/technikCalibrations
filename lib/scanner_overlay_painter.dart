import 'package:flutter/material.dart';

class ScannerOverlayPainter extends CustomPainter {
  final double widthFactor;
  final double heightFactor;

  ScannerOverlayPainter({
    required this.widthFactor,
    required this.heightFactor,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final double scanWidth = size.width * widthFactor;
    final double scanHeight = size.height * heightFactor;
    final double left = (size.width - scanWidth) / 2;
    final double top = (size.height - scanHeight) / 2;
    final Rect scanRect = Rect.fromLTWH(left, top, scanWidth, scanHeight);

    // 1. Draw Background with Cutout
    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Create a path that covers the whole screen
    final Path backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create a path for the cutout
    final Path cutoutPath = Path()..addRect(scanRect);

    // Combine them using difference to create a hole
    final Path finalPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(finalPath, backgroundPaint);

    // 2. Draw Border
    final Paint borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRect(scanRect, borderPaint);

    // 3. Draw Dividers - REMOVED

    // 4. Draw Labels - REMOVED
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.widthFactor != widthFactor ||
        oldDelegate.heightFactor != heightFactor;
  }
}
