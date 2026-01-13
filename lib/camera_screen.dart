import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'dart:io';

// Firebase Imports
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'input_image_converter.dart';
import 'roughness_reading.dart';
import 'text_recognition_service.dart';
import 'camera_manager.dart';
import 'scanner_overlay_painter.dart';

class CameraScreen extends StatefulWidget {
  final String srfId;
  final String? jobId;

  const CameraScreen({super.key, required this.srfId, this.jobId});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _cameraManager = CameraManager();
  bool _isPermissionGranted = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Overlay Rect
  Rect? _scanRect;

  // OCR & Stability
  final _textRecognitionService = TextRecognitionService();
  bool _isScanning = false;
  bool _isScanComplete = false;
  RoughnessReading? _lastReading;
  String? _capturedImage;

  // Stability Buffers
  // We require the SAME value to be seen N times consecutively to be "Confident"
  // Stability Buffers (Voting)
  // Rolling buffer of last 15 values
  final List<double?> _raBuffer = [];
  final List<double?> _rmaxBuffer = [];
  final List<double?> _rzBuffer = [];
  static const int _bufferSize = 15;
  static const int _requiredVotes = 10;

  double? _stableRa;
  double? _stableRmax;
  double? _stableRz;

  // Debug info for UI (optional, helpful to see buffer status)
  int _raVotes = 0;
  int _rmaxVotes = 0;
  int _rzVotes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;
      setState(() {
        _isPermissionGranted = true;
      });

      try {
        await _cameraManager.initialize();
        // Set Zoom to 2.0x for better OCR details
        await _cameraManager.controller?.setZoomLevel(2.0);
        _cameraManager.startImageStream(_processImage);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isPermissionGranted = false;
        _errorMessage = 'Camera permission denied via settings.';
      });
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isScanning) return; // Throttle
    if (!mounted) return;

    _isScanning = true;

    try {
      final inputImage = InputImageConverter.convert(
        image: image,
        camera: _cameraManager.cameraDescription!,
      );

      if (inputImage != null) {
        final reading = await _textRecognitionService.processImage(inputImage);

        if (mounted) {
          // Update buffers
          _updateBuffer(_raBuffer, reading.ra);
          _updateBuffer(_rmaxBuffer, reading.rmax);
          _updateBuffer(_rzBuffer, reading.rz);

          // Get stable values (Mode logic)
          final bestRa = _getStableValue(_raBuffer);
          final bestRmax = _getStableValue(_rmaxBuffer);
          final bestRz = _getStableValue(_rzBuffer);

          // Track votes for UI display
          _raVotes = _countOccurrences(_raBuffer, bestRa);
          _rmaxVotes = _countOccurrences(_rmaxBuffer, bestRmax);
          _rzVotes = _countOccurrences(_rzBuffer, bestRz);

          // Physics Validation
          bool isValid = false;
          if (bestRa != null && bestRmax != null && bestRz != null) {
            isValid = _isValidReading(bestRa, bestRmax, bestRz);
          }

          // Update stable state ONLY if valid or just keep previous?
          // The user requirement implies we should only "consider the reading Stable" if Mode >= 10.
          // We have bestRa etc.
          // But we also need them to be PHYSICALLY valid together to "stop".
          // Let's show the "best" values we have, but indicate lock status.

          _stableRa = bestRa;
          _stableRmax = bestRmax;
          _stableRz = bestRz;

          // Calculate a "Confidence" (Stability %) for display
          double calcConf(int votes) =>
              votes >= _requiredVotes ? 1.0 : (votes / _requiredVotes);

          final displayReading = RoughnessReading(
            ra: _stableRa,
            raConfidence: calcConf(_raVotes),
            rmax: _stableRmax,
            rmaxConfidence: calcConf(_rmaxVotes),
            rz: _stableRz,
            rzConfidence: calcConf(_rzVotes),
          );

          setState(() {
            _lastReading = displayReading;

            // Auto-stop condition: All stable AND Valid
            if (!_isScanComplete &&
                _stableRa != null &&
                _stableRmax != null &&
                _stableRz != null &&
                isValid) {
              _isScanComplete = true;
              _cameraManager.stopImageStream();
              _captureEvidence();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      if (!_isScanComplete) {
        _isScanning = false;
      }
    }
  }

  void _updateBuffer(List<double?> buffer, double? value) {
    // Add value (even if null, to represent "missed frame")
    // or should we only add non-nulls?
    // "last 15 detected values" vs "15 frames".
    // If I add nulls, I punish missing frames (good for stability).
    // If I don't, I prolong the history (bad if user moved).
    // Let's add the value as is.
    buffer.add(value);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0); // FIFO
    }
  }

  double? _getStableValue(List<double?> buffer) {
    if (buffer.isEmpty) return null;

    // Calculate Mode
    final frequency = <double, int>{};
    for (var val in buffer) {
      if (val != null) {
        frequency[val] = (frequency[val] ?? 0) + 1;
      }
    }

    if (frequency.isEmpty) return null;

    double? mode;
    int maxCount = 0;

    frequency.forEach((val, count) {
      if (count > maxCount) {
        maxCount = count;
        mode = val;
      }
    });

    // Requirement: "Appear in >= 10 of the 15 frames"
    if (maxCount >= _requiredVotes) {
      return mode;
    }
    return null;
  }

  int _countOccurrences(List<double?> buffer, double? target) {
    if (target == null) return 0;
    return buffer.where((v) => v == target).length;
  }

  bool _isValidReading(double ra, double rmax, double rz) {
    // 1. Ra must be smaller than Rmax
    if (ra >= rmax) return false;

    // 2. Ra > 50.0 is suspicious (missed decimal point?)
    if (ra > 50.0) return false;

    return true;
  }

  Future<void> _captureEvidence() async {
    try {
      // Small delay to ensure stream is stopped?
      // Actually, takePicture while streaming on some Android devices might be tricky,
      // but stopping stream first is good practice.
      final file = await _cameraManager.controller?.takePicture();
      if (mounted) {
        setState(() {
          _capturedImage = file?.path;
        });
      }
    } catch (e) {
      debugPrint("Error capturing evidence: $e");
    }
  }

  void _restartScan() {
    setState(() {
      _lastReading = null;
      _capturedImage = null;
      _isScanComplete = false;
      _isScanning = false;

      _stableRa = null;
      _stableRmax = null;
      _stableRz = null;
      _raVotes = 0;
      _rmaxVotes = 0;
      _rzVotes = 0;

      _raBuffer.clear();
      _rmaxBuffer.clear();
      _rzBuffer.clear();
    });
    _cameraManager.startImageStream(_processImage);
  }

  Future<void> _saveResult() async {
    if (_lastReading == null || _capturedImage == null) return;

    // 1. Show Persistent Loading SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving Data...'),
        duration: Duration(minutes: 5), // Keep visible until manually cleared
      ),
    );

    try {
      String? evidenceUrl;

      // 2. Upload Image to Storage (if jobId is present)
      if (widget.jobId != null) {
        final file = File(_capturedImage!);
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('evidence')
            .child('${widget.jobId}.jpg');

        await storageRef.putFile(file);
        evidenceUrl = await storageRef.getDownloadURL();
      }

      // 3. Update Firestore
      if (widget.jobId != null) {
        // No second toast needed

        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.jobId)
            .update({
              'status': 'Completed',
              'readings': {
                'ra': _lastReading!.ra,
                'rmax': _lastReading!.rmax,
                'rz': _lastReading!.rz,
              },
              'evidence_url': evidenceUrl,
              'calibration_date': FieldValue.serverTimestamp(),
              'calibrated_by': FirebaseAuth.instance.currentUser?.email,
            });
      } else {
        // Fallback for testing without Job ID
        debugPrint("No Job ID provided, skipping Firestore update.");
      }

      if (!mounted) return;

      // 4. Success Dialog (Clear SnackBar first)
      ScaffoldMessenger.of(context).clearSnackBars();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Success"),
          content: Text("Job ${widget.jobId ?? 'Unknown'} Completed!"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close Dialog
                Navigator.pop(context); // Back to List
              },
              child: const Text("Done"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraManager.stopImageStream();
    _cameraManager.dispose();
    _textRecognitionService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle camera usage when app is backgrounded/foregrounded
    if (!_cameraManager.isInitialized || _cameraManager.controller == null)
      return;

    if (state == AppLifecycleState.inactive) {
      _cameraManager.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      );
    }

    if (!_isPermissionGranted) {
      return const Scaffold(
        body: Center(
          child: Text('Camera permission is required to use this feature.'),
        ),
      );
    }

    if (!_cameraManager.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Initialize Rect if needed (First frame)
    final size = MediaQuery.of(context).size;
    if (_scanRect == null) {
      final scanW = size.width * 0.8;
      final scanH = size.height * 0.15;
      final left = (size.width - scanW) / 2;
      final top = size.height * 0.25; // 25% from top
      _scanRect = Rect.fromLTWH(left, top, scanW, scanH);
    }

    // Ensure Safe Access
    final rect = _scanRect!;

    // Helper to build a drag handle dot
    Widget buildHandle({
      required double left,
      required double top,
      required void Function(DragUpdateDetails) onPanUpdate,
    }) {
      return Positioned(
        left: left - 12, // Center the 24x24 touch target
        top: top - 12,
        child: GestureDetector(
          onPanUpdate: onPanUpdate,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraManager.controller!),

          // Job Info Banner
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Job: ${widget.jobId ?? widget.srfId}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),

          // Overlay Painter (Cutout & Border)
          CustomPaint(painter: ScannerOverlayPainter(scanRect: rect)),

          // --- Drag Handles (Only when scanning) ---
          if (!_isScanComplete) ...[
            // Top Center
            buildHandle(
              left: rect.center.dx,
              top: rect.top,
              onPanUpdate: (d) {
                setState(() {
                  double newTop = (rect.top + d.delta.dy).clamp(
                    0.0,
                    rect.bottom - 40,
                  );
                  _scanRect = Rect.fromLTRB(
                    rect.left,
                    newTop,
                    rect.right,
                    rect.bottom,
                  );
                });
              },
            ),
            // Bottom Center
            buildHandle(
              left: rect.center.dx,
              top: rect.bottom,
              onPanUpdate: (d) {
                setState(() {
                  double newBottom = (rect.bottom + d.delta.dy).clamp(
                    rect.top + 40,
                    size.height,
                  );
                  _scanRect = Rect.fromLTRB(
                    rect.left,
                    rect.top,
                    rect.right,
                    newBottom,
                  );
                });
              },
            ),
            // Left Center
            buildHandle(
              left: rect.left,
              top: rect.center.dy,
              onPanUpdate: (d) {
                setState(() {
                  double newLeft = (rect.left + d.delta.dx).clamp(
                    0.0,
                    rect.right - 40,
                  );
                  _scanRect = Rect.fromLTRB(
                    newLeft,
                    rect.top,
                    rect.right,
                    rect.bottom,
                  );
                });
              },
            ),
            // Right Center
            buildHandle(
              left: rect.right,
              top: rect.center.dy,
              onPanUpdate: (d) {
                setState(() {
                  double newRight = (rect.right + d.delta.dx).clamp(
                    rect.left + 40,
                    size.width,
                  );
                  _scanRect = Rect.fromLTRB(
                    rect.left,
                    rect.top,
                    newRight,
                    rect.bottom,
                  );
                });
              },
            ),
          ],

          // Debug / Result Overlay (Moved to Bottom)
          Positioned(
            bottom: 30, // Bottom aligned
            left: 20,
            right: 20,
            child: _buildGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _isScanComplete ? "Scan Complete" : "Scanning...",
                      style: TextStyle(
                        color: _isScanComplete
                            ? Colors.white
                            : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildResultRow("Ra", _lastReading?.ra),
                    _buildResultRow("Rmax", _lastReading?.rmax),
                    _buildResultRow("Rz", _lastReading?.rz),

                    if (_isScanComplete) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildGlassButton(
                            text: "Rescan",
                            icon: Icons.refresh,
                            onPressed: _restartScan,
                            isPrimary: false,
                          ),
                          _buildGlassButton(
                            text: "Save",
                            icon: Icons.save,
                            onPressed: _saveResult,
                            isPrimary: true,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, double? value) {
    // Determine confidence from matching stability field or pass it in?
    // Simplified: We can lookup from _lastReading if we passed confidence there.

    double confidence = 0.0;
    if (label == "Ra") confidence = _lastReading?.raConfidence ?? 0.0;
    if (label == "Rmax") confidence = _lastReading?.rmaxConfidence ?? 0.0;
    if (label == "Rz") confidence = _lastReading?.rzConfidence ?? 0.0;

    final percent = (confidence * 100).toInt();
    final isLocked = percent >= 90; // Just visual indicator

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          Row(
            children: [
              if (value != null)
                isLocked
                    ? const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.greenAccent,
                          size: 16,
                        ),
                      )
                    : Text(
                        "$percent% ",
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
              Text(
                value != null ? value.toString() : "--",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary
              ? Colors.greenAccent.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isPrimary
                ? Colors.greenAccent.withOpacity(0.5)
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.greenAccent : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: isPrimary ? Colors.greenAccent : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
