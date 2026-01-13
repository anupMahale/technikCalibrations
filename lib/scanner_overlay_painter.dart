import 'package:flutter/material.dart';

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanRect;

  ScannerOverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
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

    // 2. Draw Border (Glass Style: Translucent White)
    final Paint borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Use RRect for slightly rounded corners if desired, or just Rect
    // Matching the Glass Card radius (20) might be nice, but let's stick to Rect or small radius
    final RRect borderRRect = RRect.fromRectAndRadius(
      scanRect,
      const Radius.circular(12),
    );
    canvas.drawRRect(borderRRect, borderPaint);

    // Optional: Add corner accents?
    // For now, simple glass border as requested.
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}
