import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class HudPrePostPage extends StatefulWidget {
  final CameraDescription camera;

  const HudPrePostPage({super.key, required this.camera});

  @override
  State<HudPrePostPage> createState() => _HudPrePostPageState();
}

class _HudPrePostPageState extends State<HudPrePostPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late FaceDetector _faceDetector;

  bool _processing = false;
  List<Face> _faces = [];

  @override
  void initState() {
    super.initState();

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller.initialize();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: false,
      ),
    );

    _controller.startImageStream(_processCameraImage);
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_processing) return;
    _processing = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final InputImageRotation rotation =
          InputImageRotationValue.fromRawValue(widget.camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

      final InputImageFormat format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
        });
      }
    } catch (e) {
      debugPrint("❌ Errore analisi frame: $e");
    } finally {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                CustomPaint(
                  painter: _FacePainter(_faces),
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

class _FacePainter extends CustomPainter {
  final List<Face> faces;
  _FacePainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.greenAccent;

    for (final face in faces) {
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
      if (face.landmarks.containsKey(FaceLandmarkType.mouthLeft)) {
        pts.add(Offset(
          face.landmarks[FaceLandmarkType.mouthLeft]!.position.x.toDouble(),
          face.landmarks[FaceLandmarkType.mouthLeft]!.position.y.toDouble(),
        ));
      }
      if (face.landmarks.containsKey(FaceLandmarkType.mouthRight)) {
        pts.add(Offset(
          face.landmarks[FaceLandmarkType.mouthRight]!.position.x.toDouble(),
          face.landmarks[FaceLandmarkType.mouthRight]!.position.y.toDouble(),
        ));
      }

      if (pts.length > 1) {
        for (int i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(pts[i], pts[i + 1], paint);
        }
      }

      for (final p in pts) {
        canvas.drawCircle(p, 4, Paint()..color = Colors.redAccent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
