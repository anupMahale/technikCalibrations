import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class InputImageConverter {
  static InputImage? convert({
    required CameraImage image,
    required CameraDescription camera,
  }) {
    InputImageFormat? format = InputImageFormatValue.fromRawValue(
      image.format.raw,
    );

    // Explicit fallback logic
    if (format == null) {
      if (Platform.isAndroid && image.format.raw == 17) {
        format = InputImageFormat.nv21;
      } else if (Platform.isAndroid && image.format.raw == 35) {
        format = InputImageFormat.yuv420;
      } else if (Platform.isIOS &&
          image.format.group == ImageFormatGroup.bgra8888) {
        format = InputImageFormat.bgra8888;
      }
    }

    if (format == null) {
      // Debug print to help identify unknown formats
      print('Unsupported camera image format: ${image.format.raw}');
      return null;
    }

    final plane = image.planes.first;

    // Concatenate all planes for bytes
    final allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final size = Size(image.width.toDouble(), image.height.toDouble());

    final rotation = _getRotation(camera);

    final inputImageMetadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  static InputImageRotation _getRotation(CameraDescription camera) {
    // We locked orientation to PortraitUp in main.dart
    // So device orientation is implicitly PortraitUp (0 degrees)
    // Sensor orientation is usually 90 on mobile devices for back camera in portrait

    // Simplified logic assuming Portrait Mode lock:
    final sensorOrientation = camera.sensorOrientation;

    // Map sensor orientation to InputImageRotation
    // For back camera:
    // 90 -> rotation90deg
    // etc.
    // Since we are in portrait, the "up" of the image is usually 90 degrees offset from raw sensor data

    // Common mapping for Android/iOS back camera in Portrait:
    // Android: sensor=90 -> needs 90 rotation
    // iOS: often handled via BGRA but rotation metadata still matters

    return InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;
  }
}
