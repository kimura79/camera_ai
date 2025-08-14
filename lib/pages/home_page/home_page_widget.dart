import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

enum CaptureMode { volto, particolare }

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;

  CaptureMode _mode = CaptureMode.volto;
  final double _targetMmPerPx = 0.117;
  final double _ipdMm = 63.0;
  double get _targetPx => _ipdMm / _targetMmPerPx; // ~539 px
  double _lastIpdPx = 0.0;
  bool _scaleOk = false;

  String? _lastPhotoPath;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    _cameraIndex = 0;
    await _startController(_cameras[_cameraIndex]);
  }

  Future<void> _startController(CameraDescription desc) async {
    final ctrl = CameraController(
      desc,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    await ctrl.setFlashMode(FlashMode.off);
    await ctrl.startImageStream(_processCameraImage);
    setState(() {
      _controller = ctrl;
      _initializing = false;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    await _startController(_cameras[_cameraIndex]);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 300) return;
    _lastProc = now;

    final rotation = _rotationFromSensor(_controller!.description.sensorOrientation);
    final inputImage = _inputImageFromCameraImage(image, rotation);
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      _updateScale(null);
      return;
    }
    final left = faces.first.landmarks[FaceLandmarkType.leftEye];
    final right = faces.first.landmarks[FaceLandmarkType.rightEye];
    if (left == null || right == null) {
      _updateScale(null);
      return;
    }
    final dx = left.position.x - right.position.x;
    final dy = left.position.y - right.position.y;
    _updateScale(math.sqrt(dx * dx + dy * dy));
  }

  void _updateScale(double? ipdPx) {
    final double tgt = _targetPx;
    final double minT = tgt * 0.95;
    final double maxT = tgt * 1.05;
    bool ok = false;
    if (ipdPx != null && ipdPx.isFinite) {
      ok = ipdPx >= minT && ipdPx <= maxT;
    }
    setState(() {
      _lastIpdPx = ipdPx ?? 0;
      _scaleOk = ok;
    });
  }

  InputImageRotation _rotationFromSensor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _inputImageFromCameraImage(CameraImage image, InputImageRotation rotation) {
    final b = BytesBuilder();
    for (final plane in image.planes) {
      b.add(plane.bytes);
    }
    return InputImage.fromBytes(
      bytes: b.toBytes(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _takeAndSavePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final file = await _controller!.takePicture();
    final imageBytes = await File(file.path).readAsBytes();
    img.Image? captured = img.decodeImage(imageBytes);
    if (captured == null) return;

    final shorterSide = math.min(captured.width, captured.height);
    final cropSize = (shorterSide * 0.70).roundToDouble();
    final centerX = (captured.width / 2).round();
    final centerY = (captured.height / 2.3).round();

    final left = (centerX - cropSize / 2).clamp(0, captured.width - cropSize).toInt();
    final top = (centerY - cropSize / 2).clamp(0, captured.height - cropSize).toInt();

    img.Image cropped = img.copyCrop(captured, x: left, y: top, width: cropSize.toInt(), height: cropSize.toInt());

    if (_controller!.description.lensDirection == CameraLensDirection.front) {
      cropped = img.flipHorizontal(cropped);
    }

    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outBytes = img.encodeJpg(cropped);
    await File(outPath).writeAsBytes(outBytes);

    await ImageGallerySaver.saveFile(outPath);
    setState(() {
      _lastPhotoPath = outPath;
    });
  }

  Widget _buildCameraPreview() {
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile', style: TextStyle(color: Colors.white)));
    }

    final isFront = _controller!.description.lensDirection == CameraLensDirection.front;
    Widget preview = CameraPreview(_controller!);
    if (isFront) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..rotateY(math.pi),
        child: preview,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
        LayoutBuilder(builder: (context, constraints) {
          final shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
          final squareSize = shortSide * 0.70;
          final frameColor = _scaleOk ? Colors.green : Colors.yellow.withOpacity(0.9);

          return Align(
            alignment: const Alignment(0, -0.3),
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                border: Border.all(color: frameColor, width: 5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Thumbnail a sinistra
          GestureDetector(
            onTap: () {
              if (_lastPhotoPath != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(child: Image.file(File(_lastPhotoPath!))),
                    ),
                  ),
                );
              }
            },
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                image: _lastPhotoPath != null
                    ? DecorationImage(image: FileImage(File(_lastPhotoPath!)), fit: BoxFit.cover)
                    : null,
                color: Colors.black26,
              ),
              child: _lastPhotoPath == null
                  ? const Icon(Icons.photo, color: Colors.white)
                  : null,
            ),
          ),
          // Pulsante scatto
          FloatingActionButton(
            onPressed: _scaleOk ? _takeAndSavePicture : null,
            backgroundColor: _scaleOk ? Colors.blue : Colors.grey,
            child: const Icon(Icons.camera_alt),
          ),
          // Switch camera a destra
          GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.cameraswitch, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'VOLTO'),
              Tab(text: 'PARTICOLARE'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Stack(
              children: [
                Positioned.fill(child: _buildCameraPreview()),
                Align(alignment: Alignment.bottomCenter, child: _buildBottomBar()),
              ],
            ),
            Stack(
              children: [
                Positioned.fill(child: _buildCameraPreview()),
                Align(alignment: Alignment.bottomCenter, child: _buildBottomBar()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}