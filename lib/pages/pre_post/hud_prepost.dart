import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart'; // ✅ Mediapipe plugin

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

  List<Offset> _guidePoints = [];
  List<Offset> _livePoints = [];

  final FaceMeshDetector _faceMesh = FaceMeshDetector(
    maxFaces: 1,
    refineLandmarks: true,
  );

  List<CameraDescription> _cameras = [];
  late CameraDescription _currentCamera;

  bool _shooting = false;
  double _alignmentScore = 0.0;

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
        final results = await _faceMesh.processImage(decoded);
        if (results.isNotEmpty) {
          setState(() {
            _guidePoints =
                _extractLandmarks(results.first, decoded.width, decoded.height);
          });
        }
      }
    } catch (e) {
      debugPrint("Errore landmark PRE: $e");
    }
  }

  List<Offset> _extractLandmarks(FaceMeshFace face, int w, int h) {
    // stessi indici usati lato server
    final ids = [33, 263, 1, 13, 14]; // sx occhio, dx occhio, naso, bocca sup, bocca inf
    return ids.map((i) {
      final lm = face.landmarks[i];
      return Offset(lm.x * w, lm.y * h);
    }).toList();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final results = await _faceMesh.processCameraImage(image);
      if (results.isNotEmpty) {
        final points =
            _extractLandmarks(results.first, image.width, image.height);
        setState(() {
          _livePoints = points;
          _alignmentScore = _computeAlignment(
              _guidePoints, _livePoints, image.width.toDouble(), image.height.toDouble());
        });
      }
    } catch (e) {
      debugPrint("Errore landmark live: $e");
    }
  }

  double _computeAlignment(
      List<Offset> guide, List<Offset> live, double w, double h) {
    if (guide.isEmpty || live.isEmpty || guide.length != live.length) return 0;

    double distSum = 0;
    for (int i = 0; i < guide.length; i++) {
      final dx = (guide[i].dx / w) - (live[i].dx / w);
      final dy = (guide[i].dy / h) - (live[i].dy / h);
      distSum += math.sqrt(dx * dx + dy * dy);
    }
    final avgDist = distSum / guide.length;
    return (1.0 - avgDist * 2).clamp(0.0, 1.0);
  }

  Future<void> _takePicture() async {
    try {
      if (_shooting) return;
      setState(() => _shooting = true);

      await _controller.stopImageStream();
      final image = await _controller.takePicture();
      if (!mounted) return;

      File file = File(image.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded != null) {
        final side = decoded.width < decoded.height ? decoded.width : decoded.height;
        final x = (decoded.width - side) ~/ 2;
        final y = (decoded.height - side) ~/ 2;
        img.Image cropped =
            img.copyCrop(decoded, x: x, y: y, width: side, height: side);
        cropped = img.copyResize(cropped, width: 1024, height: 1024);
        if (_currentCamera.lensDirection == CameraLensDirection.front) {
          cropped = img.flipHorizontal(cropped);
        }
        final outPath = "${file.path}_square.jpg";
        file = await File(outPath).writeAsBytes(img.encodeJpg(cropped));
      }

      Navigator.pop(context, file);
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
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
  void dispose() {
    _controller.dispose();
    _faceMesh.close();
    super.dispose();
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
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
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
    final redPaint = Paint()..color = Colors.red;
    final bluePaint = Paint()..color = Colors.blue;

    for (final p in guidePoints) {
      canvas.drawCircle(p, 6, redPaint);
    }
    for (final p in livePoints) {
      canvas.drawCircle(p, 6, bluePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
