// 🔹 home_page_widget.dart — Fullscreen cover + overlay cover, volto in scala 0,117; crop 1024x1024

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

// ML Kit usato in modalità "volto"
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

enum CaptureMode { volto, particolare }

class _HomePageWidgetState extends State<HomePageWidget>
    with WidgetsBindingObserver {
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;

  String? _lastShotPath;

  // Modalità selezionata
  CaptureMode _mode = CaptureMode.volto;

  // ====== Parametri scala ======
  final double _targetMmPerPx = 0.117; // mm/px

  // Volto (ML Kit, IPD)
  double _ipdMm = 63.0;
  double get _targetPxVolto => _ipdMm / _targetMmPerPx; // ~539 px
  double _lastIpdPx = 0.0; // IPD misurata in px nella preview
  bool _scaleOkVolto = false;

  // Particolare (12 cm) — lasciata COM'È per ora
  static const double _targetMmPart = 120.0; // 12 cm
  double get _targetPxPart => _targetMmPart / _targetMmPerPx; // ~1026 px
  bool get _scaleOkPart {
    final double minT = _targetPxPart * 0.95; // ~974
    final double maxT = _targetPxPart * 1.05; // ~1077
    const double cropSidePx = 1024.0;
    return cropSidePx >= minT && cropSidePx <= maxT;
  }

  // ====== ML Kit ======
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);
  bool _streamRunning = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
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
      final backIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back);
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
      await ctrl.setZoomLevel(1.0); // 🔒 Zoom fisso 1×
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

  // ====== Stream → ML Kit solo in modalità "volto" ======
  Future<void> _processCameraImage(CameraImage image) async {
    if (_mode != CaptureMode.volto) return;
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
        _updateScaleVolto(null);
        return;
      }
      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        _updateScaleVolto(null);
        return;
      }
      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      _updateScaleVolto(distPx);
    } catch (_) {}
  }

  void _updateScaleVolto(double? ipdPx) {
    final double tgt = _targetPxVolto;
    final double minT = tgt * 0.95;
    final double maxT = tgt * 1.05;

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

  // ====== Helpers ML Kit ======
  InputImageRotation _rotationFromSensor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _inputImageFromCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final b = BytesBuilder(copy: false);
    for (final Plane plane in image.planes) {
      b.add(plane.bytes);
    }
    final Uint8List bytes = b.toBytes();

    final Size size = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: InputImageFormat.yuv420,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ====== Scatto + salvataggio ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      if (_streamRunning) {
        await ctrl.stopImageStream();
        _streamRunning = false;
      }

      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      final img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      // ===== Crop coerente con riquadro (VOLTO in scala 0,117) =====
      img.Image cropped;

      if (_mode == CaptureMode.volto && _lastIpdPx > 0) {
        // scalaFattore = (mm/px attuale) / (mm/px target)
        final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
        final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;

        // Lato crop nel RAW = lato corto RAW / scalaFattore (centrato)
        final int shortRaw = math