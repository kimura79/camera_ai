import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;

/// Pagina HUD Pre/Post con guida landmark
class HudPrePostPage extends StatefulWidget {
  final CameraDescription camera;
  final String preImage; // immagine guida PRE

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
  bool _isDetecting = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  List<Face> _faces = [];

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      _controller.startImageStream(_processCameraImage);
    });
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
      final WriteBuffer allBytes = WriteBuffer();
      for (var plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final camera = widget.camera;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final planeData = image.planes.map(
        (plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        },
      ).toList();

      final inputImageData = InputImageData(
        size: imageSize,
        imageRotation: imageRotation,
        inputImageFormat: inputImageFormat,
        planeData: planeData,
      );

      final inputImage =
          InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
        });
      }
    } catch (e) {
      debugPrint("❌ Errore FaceDetector: $e");
    } finally {
      _isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                // Immagine guida PRE semi-trasparente
                Opacity(
                  opacity: 0.3,
                  child: Image.file(
                    File(widget.preImage),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                // HUD con landmarks verdi
                CustomPaint(
                  painter: FacePainter(_faces),
                  child: Container(),
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

class FacePainter extends CustomPainter {
  final List<Face> faces;

  FacePainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.green;

    for (final face in faces) {
      // rettangolo viso
      canvas.drawRect(face.boundingBox, paint);

      // landmark occhi
      if (face.landmarks.containsKey(FaceLandmarkType.leftEye)) {
        final leftEye = face.landmarks[FaceLandmarkType.leftEye]!;
        canvas.drawCircle(Offset(leftEye.position.x.toDouble(),
            leftEye.position.y.toDouble()), 4, paint);
      }
      if (face.landmarks.containsKey(FaceLandmarkType.rightEye)) {
        final rightEye = face.landmarks[FaceLandmarkType.rightEye]!;
        canvas.drawCircle(Offset(rightEye.position.x.toDouble(),
            rightEye.position.y.toDouble()), 4, paint);
      }

      // landmark naso
      if (face.landmarks.containsKey(FaceLandmarkType.noseBase)) {
        final nose = face.landmarks[FaceLandmarkType.noseBase]!;
        canvas.drawCircle(
            Offset(nose.position.x.toDouble(), nose.position.y.toDouble()),
            4,
            paint);
      }

      // landmark bocca aggiornati
      if (face.landmarks.containsKey(FaceLandmarkType.leftMouth)) {
        final lm = face.landmarks[FaceLandmarkType.leftMouth]!;
        canvas.drawCircle(
            Offset(lm.position.x.toDouble(), lm.position.y.toDouble()),
            4,
            paint);
      }
      if (face.landmarks.containsKey(FaceLandmarkType.rightMouth)) {
        final rm = face.landmarks[FaceLandmarkType.rightMouth]!;
        canvas.drawCircle(
            Offset(rm.position.x.toDouble(), rm.position.y.toDouble()),
            4,
            paint);
      }
      if (face.landmarks.containsKey(FaceLandmarkType.bottomMouth)) {
        final bm = face.landmarks[FaceLandmarkType.bottomMouth]!;
        canvas.drawCircle(
            Offset(bm.position.x.toDouble(), bm.position.y.toDouble()),
            4,
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
