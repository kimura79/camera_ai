import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;

enum CaptureMode { volto, particolare }

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;
  bool _streamRunning = false;

  String? _lastShotPath;

  CaptureMode _mode = CaptureMode.volto;

  static const double _targetMmPerPx = 0.117;
  static const double _ipdMm = 63.0;
  static const double _overlayYOffset = -0.3;
  static const double _tolerance = 0.05;
  static const double _frameThickness = 6.0;

  double get _targetPxVolto => _ipdMm / _targetMmPerPx;
  double _lastIpdPx = 0.0;
  bool _scaleOkVolto = false;

  bool get _scaleOkPart {
    if (_lastIpdPx <= 0) return false;
    final mmPerPxAttuale = _ipdMm / _lastIpdPx;
    final err = (mmPerPxAttuale - _targetMmPerPx).abs() / _targetMmPerPx;
    return err <= _tolerance;
  }

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
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _initializing = false);
        return;
      }
      final backIndex = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = backIndex >= 0 ? backIndex : 0;
      await _startController(_cameras[_cameraIndex]);
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() => _initializing = false);
    }
  }

  Future<void> _startController(CameraDescription desc) async {
    final ctrl = CameraController(
      desc,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      await ctrl.setZoomLevel(1.0);
      await ctrl.startImageStream(_processCameraImage);
      _streamRunning = true;
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      debugPrint('Controller start error: $e');
      await ctrl.dispose();
      setState(() => _initializing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final old = _controller;
    _controller = null;
    try {
      if (_streamRunning) {
        await old?.stopImageStream();
        _streamRunning = false;
      }
    } catch (_) {}
    await old?.dispose();
    await _startController(_cameras[_cameraIndex]);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 300) return;
    _lastProc = now;

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      final rotation = _rotationFromSensor(ctrl.description.sensorOrientation);
      final inputImage = _inputImageFromCameraImage(image, rotation);

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        _updateScaleFromIpd(null);
        return;
      }
      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        _updateScaleFromIpd(null);
        return;
      }
      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      _updateScaleFromIpd(distPx);
    } catch (_) {}
  }

  void _updateScaleFromIpd(double? ipdPx) {
    final double tgt = _targetPxVolto;
    final double minT = tgt * (1.0 - _tolerance);
    final double maxT = tgt * (1.0 + _tolerance);

    bool ok = false;
    double shown = 0;
    if (ipdPx != null && ipdPx.isFinite) {
      shown = ipdPx;
      ok = (ipdPx >= minT && ipdPx <= maxT);
    }
    if (!mounted) return;
    setState(() {
      _lastIpdPx = shown;
      _scaleOkVolto = ok;
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

  /// CORRETTO PER iOS
  InputImage _inputImageFromCameraImage(
      CameraImage image, InputImageRotation rotation) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final InputImageFormat inputImageFormat =
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

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: rotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    return InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
  }

  Future<void> _takeAndSavePicture() async {
    if (_shooting || _controller == null) return;
    setState(() => _shooting = true);

    try {
      final file = await _controller!.takePicture();
      final imgBytes = await File(file.path).readAsBytes();
      final decoded = img.decodeImage(imgBytes);
      if (decoded != null) {
        // 🔹 Qui salvi esattamente il crop della preview
        final int size = math.min(decoded.width, decoded.height);
        final int offsetX = ((decoded.width - size) / 2).round();
        final int offsetY = ((decoded.height - size) / 2).round();
        final cropped =
            img.copyCrop(decoded, x: offsetX, y: offsetY, width: size, height: size);
        final savedBytes = img.encodeJpg(cropped);
        final res = await ImageGallerySaver.saveImage(Uint8List.fromList(savedBytes));
        debugPrint("📸 Salvata immagine: $res");
        setState(() => _lastShotPath = file.path);
      }
    } catch (e) {
      debugPrint('Errore scatto: $e');
    } finally {
      setState(() => _shooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: Text("Nessuna camera trovata")));
    }
    return Scaffold(
      key: scaffoldKey,
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                    icon: const Icon(Icons.switch_camera),
                    onPressed: _switchCamera),
                IconButton(
                    icon: Icon(
                      Icons.camera,
                      color: _shooting ? Colors.grey : Colors.white,
                    ),
                    onPressed: _takeAndSavePicture),
              ],
            ),
          )
        ],
      ),
    );
  }
}