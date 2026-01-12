import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraManager {
  static final CameraManager _instance = CameraManager._internal();

  factory CameraManager() {
    return _instance;
  }

  CameraManager._internal();

  CameraController? _controller;
  CameraDescription? _cameraDescription;
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  CameraDescription? get cameraDescription => _cameraDescription;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras found');
      }

      // Find the first rear camera
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraDescription = rearCamera;

      _controller = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false, // Clean setup for image capture
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      rethrow;
    }
  }

  Future<void> startImageStream(Function(CameraImage) onAvailable) async {
    if (!_isInitialized || _controller == null) return;
    try {
      await _controller!.startImageStream(onAvailable);
    } catch (e) {
      debugPrint('Error starting image stream: $e');
    }
  }

  Future<void> stopImageStream() async {
    if (!_isInitialized || _controller == null) return;
    try {
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}
