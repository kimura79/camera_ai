import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class HudPrePostPage extends StatefulWidget {
  final CameraDescription camera;
  final File preImage;

  const HudPrePostPage({
    super.key,
    required this.camera,
    required this.preImage,
  });

  @override
  State<HudPrePostPage> createState() => _HudPrePostPageState();
}

class _HudPrePostPageState extends State<HudPrePostPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late FaceDetector _faceDetector;

  bool _isDetecting = false;
  bool _shooting = false;
  double _alignmentScore = 0.0;

  List<Offset> _livePoints = [];
  List<Offset> _guidePoints = [];

  List<CameraDescription> _cameras = [];
  late CameraDescription _currentCamera;

  @override
  void initState() {
    super.initState();
    _currentCamera = widget.camera;

    _controller = CameraController(
      _currentCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.startImageStream(_processCameraImage);
    });

    final options = FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
    );
    _faceDetector = FaceDetector(options: options);

    _loadGuideLandmarks();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    _cameras = await availableCameras();
  }

  Future<void> _loadGuideLandmarks() async {
    try {
      final bytes = await widget.preImage.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final w = decoded.width.toDouble();
        final h = decoded.height.toDouble();
        setState(() {
          _guidePoints = [
            Offset(w * 0.3, h * 0.4), // occhio sx approx
            Offset(w * 0.7, h * 0.4), // occhio dx approx
            Offset(w * 0.5, h * 0.55), // naso approx
            Offset(w * 0.5, h * 0.75), // bocca approx
          ];
        });
      }
    } catch (e) {
      debugPrint("Errore caricamento guida: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      // 🔹 Converte CameraImage in bytes
      final allBytes = BytesBuilder();
      for (final Plane plane in image.planes) {
        allBytes.add(plane.bytes);
      }
      final bytes = allBytes.toBytes();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final landmarks = face.landmarks;

        final points = <Offset>[];
        if (landmarks[FaceLandmarkType.leftEye] != null) {
          points.add(Offset(
            landmarks[FaceLandmarkType.leftEye]!.position.x.toDouble(),
            landmarks[FaceLandmarkType.leftEye]!.position.y.toDouble(),
          ));
        }
        if (landmarks[FaceLandmarkType.rightEye] != null) {
          points.add(Offset(
            landmarks[FaceLandmarkType.rightEye]!.position.x.toDouble(),
            landmarks[FaceLandmarkType.rightEye]!.position.y.toDouble(),
          ));
        }
        if (landmarks[FaceLandmarkType.noseBase] != null) {
          points.add(Offset(
            landmarks[FaceLandmarkType.noseBase]!.position.x.toDouble(),
            landmarks[FaceLandmarkType.noseBase]!.position.y.toDouble(),
          ));
        }
        if (landmarks[FaceLandmarkType.mouthBottom] != null) {
          points.add(Offset(
            landmarks[FaceLandmarkType.mouthBottom]!.position.x.toDouble(),
            landmarks[FaceLandmarkType.mouthBottom]!.position.y.toDouble(),
          ));
        }

        setState(() {
          _livePoints = points;
        });

        // 🔹 calcolo semplice punteggio
        final cx = face.boundingBox.center.dx / image.width;
        final cy = face.boundingBox.center.dy / image.height;
        final double distX = (cx - 0.5).abs();
        final double distY = (cy - 0.5).abs();
        _alignmentScore = (1.0 - (distX + distY)).clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint("Errore face detection: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _takePicture() async {
    try {
      await _controller.stopImageStream();
      final file = await _controller.takePicture();
      if (!mounted) return;

      // 🔹 Crop 1024x1024
      File outFile = File(file.path);
      final bytes = await outFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final side =
            decoded.width < decoded.height ? decoded.width : decoded.height;
        final x = (decoded.width - side) ~/ 2;
        final y = (decoded.height - side) ~/ 2;
        img.Image cropped =
            img.copyCrop(decoded, x: x, y: y, width: side, height: side);
        cropped = img.copyResize(cropped, width: 1024, height: 1024);

        if (_currentCamera.lensDirection == CameraLensDirection.front) {
          cropped = img.flipHorizontal(cropped);
        }

        final outPath = "${file.path}_square.jpg";
        outFile = await File(outPath).writeAsBytes(img.encodeJpg(cropped));
      }

      Navigator.pop(context, outFile);
    } catch (e) {
      debugPrint("Errore scatto: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.length < 2) return;

    final newCamera = _currentCamera.lensDirection == CameraLensDirection.front
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first,
          )
        : _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first,
          );

    _currentCamera = newCamera;

    await _controller.dispose();
    _controller = CameraController(
      _currentCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller.initialize();
    _controller.startImageStream(_processCameraImage);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller),
                Center(
                  child: SizedBox(
                    width: screenW,
                    height: screenW,
                    child: Opacity(
                      opacity: 0.3,
                      child: Image.file(widget.preImage, fit: BoxFit.cover),
                    ),
                  ),
                ),
                CustomPaint(
                  painter: LandmarkPainter(
                    guidePoints: _guidePoints,
                    livePoints: _livePoints,
                  ),
                  size: Size.infinite,
                ),
                Positioned(
                  top: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      "Allineamento: ${(_alignmentScore * 100).toStringAsFixed(1)}%",
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 25),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black38,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _takePicture,
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 86,
                            height: 86,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 86,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ),
                                Container(
                                  width: 78,
                                  height: 78,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 6),
                                  ),
                                ),
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black38,
                              ),
                              child: const Icon(Icons.cameraswitch,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class LandmarkPainter extends CustomPainter {
  final List<Offset> guidePoints;
  final List<Offset> livePoints;

  LandmarkPainter({required this.guidePoints, required this.livePoints});

  @override
  void paint(Canvas canvas, Size size) {
    final redPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final bluePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // punti guida (rossi)
    for (final p in guidePoints) {
      canvas.drawCircle(p, 6, redPaint);
    }

    // punti live (blu) + linee
    for (final p in livePoints) {
      canvas.drawCircle(p, 6, bluePaint);
    }
    if (livePoints.length >= 2) {
      for (int i = 0; i < livePoints.length - 1; i++) {
        canvas.drawLine(livePoints[i], livePoints[i + 1], bluePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
