import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart'; // 🔹 Serve per WriteBuffer

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

  @override
  void initState() {
    super.initState();

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.startImageStream(_processCameraImage);
    });

    // 🔹 Configura FaceDetector
    final options = FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
    );
    _faceDetector = FaceDetector(options: options);
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
      // 🔹 Converte CameraImage → InputImage
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final InputImageRotation rotation =
          InputImageRotation.rotation0deg; // TODO: calcolare da sensorOrientation se serve

      final InputImageFormat format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        // 🔹 Calcolo punteggio di allineamento (es. occhi/naso in posizione centrale)
        final face = faces.first;
        final boundingBox = face.boundingBox;

        final cx = boundingBox.center.dx / image.width;
        final cy = boundingBox.center.dy / image.height;

        final double distX = (cx - 0.5).abs();
        final double distY = (cy - 0.5).abs();

        // punteggio semplice: più vicino al centro → più alto
        _alignmentScore = (1.0 - (distX + distY)).clamp(0.0, 1.0);

        if (_alignmentScore > 0.98 && !_shooting) {
          _shooting = true;
          await _takePicture();
        }

        setState(() {});
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
      Navigator.pop(context, File(file.path));
    } catch (e) {
      debugPrint("Errore scatto: $e");
    }
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
              children: [
                CameraPreview(_controller),
                // 🔹 Overlay con immagine guida (semi-trasparente)
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
                // 🔹 HUD con punteggio
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
