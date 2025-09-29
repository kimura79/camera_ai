import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

class HudPrePostPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final CameraDescription initialCamera;
  final File guideImage;

  const HudPrePostPage({
    super.key,
    required this.cameras,
    required this.initialCamera,
    required this.guideImage,
  });

  @override
  State<HudPrePostPage> createState() => _HudPrePostPageState();
}

class _HudPrePostPageState extends State<HudPrePostPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  late CameraDescription currentCamera;
  bool _shooting = false;
  bool _autoShotDone = false;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: false,
    ),
  );

  List<Offset> _landmarks = [];

  @override
  void initState() {
    super.initState();
    currentCamera = widget.initialCamera;
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _controller?.dispose();
    _controller = CameraController(
      currentCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller!.initialize().then((_) async {
      await _controller!.setFlashMode(FlashMode.off);
      _controller!.startImageStream(_processCameraImage);
    });
    if (mounted) setState(() {});
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_shooting || _autoShotDone) return;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final InputImageRotation rotation =
          InputImageRotation.rotation0deg; // correzione manuale se serve
      final InputImageFormat format =
          InputImageFormatMethods.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
        ),
      );

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final pts = <Offset>[];

        if (face.landmarks.containsKey(FaceLandmarkType.leftEye)) {
          pts.add(Offset(
            face.landmarks[FaceLandmarkType.leftEye]!.position.x.toDouble(),
            face.landmarks[FaceLandmarkType.leftEye]!.position.y.toDouble(),
          ));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.rightEye)) {
          pts.add(Offset(
            face.landmarks[FaceLandmarkType.rightEye]!.position.x.toDouble(),
            face.landmarks[FaceLandmarkType.rightEye]!.position.y.toDouble(),
          ));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.noseBase)) {
          pts.add(Offset(
            face.landmarks[FaceLandmarkType.noseBase]!.position.x.toDouble(),
            face.landmarks[FaceLandmarkType.noseBase]!.position.y.toDouble(),
          ));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.mouthBottom)) {
          pts.add(Offset(
            face.landmarks[FaceLandmarkType.mouthBottom]!.position.x.toDouble(),
            face.landmarks[FaceLandmarkType.mouthBottom]!.position.y.toDouble(),
          ));
        }

        setState(() {
          _landmarks = pts;
        });

        // === SCATTO AUTOMATICO SE ALLINEAMENTO AL 98% ===
        if (_calculateAlignmentScore(pts) >= 0.98) {
          _autoShotDone = true;
          await _takePicture();
        }
      } else {
        setState(() {
          _landmarks = [];
        });
      }
    } catch (e) {
      debugPrint("Errore processCameraImage: $e");
    }
  }

  double _calculateAlignmentScore(List<Offset> pts) {
    if (pts.length < 4) return 0.0;

    // Calcola distanza media tra punti reali e "ideali"
    // (per ora usiamo un placeholder molto semplice)
    double idealDistance = 100.0;
    double diff = pts.map((p) => p.distance).reduce((a, b) => a + b) /
        pts.length; // fittizio

    double score = max(0, 1 - (diff - idealDistance).abs() / idealDistance);
    return score.clamp(0.0, 1.0);
  }

  Future<void> _takePicture() async {
    try {
      if (_shooting) return;
      setState(() => _shooting = true);

      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      if (!mounted) return;

      Navigator.pop(context, File(image.path));
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller != null) {
            return Stack(
              children: [
                CameraPreview(_controller!),
                CustomPaint(
                  painter: _HudPainter(_landmarks),
                  child: Container(),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 25),
                    child: GestureDetector(
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

class _HudPainter extends CustomPainter {
  final List<Offset> landmarks;

  _HudPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final p in landmarks) {
      canvas.drawCircle(p, 6, paint);
    }

    if (landmarks.length >= 2) {
      canvas.drawLine(landmarks[0], landmarks[1], paint); // occhi
    }
    if (landmarks.length >= 4) {
      canvas.drawLine(landmarks[2], landmarks[3], paint); // naso-bocca
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
