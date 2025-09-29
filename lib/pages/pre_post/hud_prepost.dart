import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class HudPrePostPage extends StatefulWidget {
  final File preImage;

  const HudPrePostPage({super.key, required this.preImage});

  @override
  State<HudPrePostPage> createState() => _HudPrePostPageState();
}

class _HudPrePostPageState extends State<HudPrePostPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _shooting = false;

  List<Offset> _landmarksGuida = [];
  List<Offset> _landmarksLive = [];
  double _similarity = 0.0;

  late FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
      ),
    );
    _initCamera();
    _estraiLandmarksGuida();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initializeControllerFuture = _controller!.initialize().then((_) async {
      await _controller!.setFlashMode(FlashMode.off);
      _startStream();
    });
    if (mounted) setState(() {});
  }

  Future<void> _estraiLandmarksGuida() async {
    final image = InputImage.fromFile(widget.preImage);
    final faces = await _faceDetector.processImage(image);
    if (faces.isNotEmpty) {
      final face = faces.first;
      setState(() {
        _landmarksGuida = _convertLandmarks(face, MediaQuery.of(context).size);
      });
    }
  }

  void _startStream() {
    _controller!.startImageStream((image) async {
      if (!mounted) return;
      final inputImage = _toInputImage(image);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        final live = _convertLandmarks(face, MediaQuery.of(context).size);

        if (live.isNotEmpty && _landmarksGuida.isNotEmpty) {
          final sim = _calcolaSimilarita(_landmarksGuida, live);
          setState(() {
            _landmarksLive = live;
            _similarity = sim;
          });

          if (!_shooting && sim >= 0.98) {
            _shooting = true;
            _takePicture();
          }
        }
      }
    });
  }

  List<Offset> _convertLandmarks(Face face, Size screen) {
    final List<Offset> pts = [];
    if (face.landmarks.containsKey(FaceLandmarkType.leftEye)) {
      pts.add(Offset(face.landmarks[FaceLandmarkType.leftEye]!.position.x,
          face.landmarks[FaceLandmarkType.leftEye]!.position.y));
    }
    if (face.landmarks.containsKey(FaceLandmarkType.rightEye)) {
      pts.add(Offset(face.landmarks[FaceLandmarkType.rightEye]!.position.x,
          face.landmarks[FaceLandmarkType.rightEye]!.position.y));
    }
    if (face.landmarks.containsKey(FaceLandmarkType.noseBase)) {
      pts.add(Offset(face.landmarks[FaceLandmarkType.noseBase]!.position.x,
          face.landmarks[FaceLandmarkType.noseBase]!.position.y));
    }
    if (face.landmarks.containsKey(FaceLandmarkType.mouthLeft)) {
      pts.add(Offset(face.landmarks[FaceLandmarkType.mouthLeft]!.position.x,
          face.landmarks[FaceLandmarkType.mouthLeft]!.position.y));
    }
    if (face.landmarks.containsKey(FaceLandmarkType.mouthRight)) {
      pts.add(Offset(face.landmarks[FaceLandmarkType.mouthRight]!.position.x,
          face.landmarks[FaceLandmarkType.mouthRight]!.position.y));
    }
    return pts;
  }

  double _calcolaSimilarita(List<Offset> guida, List<Offset> live) {
    if (guida.isEmpty || live.isEmpty || guida.length != live.length) return 0;
    double sum = 0;
    for (int i = 0; i < guida.length; i++) {
      sum += (1 /
          (1 + (guida[i] - live[i]).distance)); // distanza -> score inverso
    }
    return sum / guida.length; // normalizza
  }

  InputImage _toInputImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final camera = _controller!.description;
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final planeData = image.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
        planeData: planeData,
      ),
    );
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      if (!mounted) return;

      File file = File(image.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded != null) {
        final side =
            decoded.width < decoded.height ? decoded.width : decoded.height;
        final x = (decoded.width - side) ~/ 2;
        final y = (decoded.height - side) ~/ 2;
        img.Image cropped =
            img.copyCrop(decoded, x: x, y: y, width: side, height: side);

        cropped = img.copyResize(cropped, width: 1024, height: 1024);

        if (_controller!.description.lensDirection ==
            CameraLensDirection.front) {
          cropped = img.flipHorizontal(cropped);
        }

        final outPath = "${file.path}_square.jpg";
        file = await File(outPath).writeAsBytes(img.encodeJpg(cropped));

        Navigator.pop(context, file);
      }
    } catch (e) {
      debugPrint("❌ Errore scatto automatico: $e");
    } finally {
      _shooting = false;
    }
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
                  painter: _HudPainter(
                    guida: _landmarksGuida,
                    live: _landmarksLive,
                  ),
                  child: Container(),
                ),
                Positioned(
                  top: 40,
                  left: 20,
                  child: Text(
                    "Allineamento: ${(_similarity * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
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
  final List<Offset> guida;
  final List<Offset> live;

  _HudPainter({required this.guida, required this.live});

  @override
  void paint(Canvas canvas, Size size) {
    final paintGuida = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final paintLive = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    for (final p in guida) {
      canvas.drawCircle(p, 5, paintGuida);
    }
    for (final p in live) {
      canvas.drawCircle(p, 5, paintLive);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
