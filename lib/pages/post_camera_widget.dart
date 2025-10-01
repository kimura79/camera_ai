// 🔹 post_camera_widget.dart — Fotocamera dedicata al POST
//    Copia di home_page_widget.dart ma adattata per flusso Pre/Post (solo UI + scatto)

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:custom_camera_component/pages/distanza_cm_overlay.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:custom_camera_component/models/capture_mode.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page/home_page_model.dart';
export 'home_page/home_page_model.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👈 overlay PRE

  const PostCameraWidget({
    super.key,
    this.guideImage,
  });

  static String routeName = 'PostCameraPage';
  static String routePath = '/postCameraPage';

  @override
  State<PostCameraWidget> createState() => _PostCameraWidgetState();
}

class _PostCameraWidgetState extends State<PostCameraWidget>
    with WidgetsBindingObserver {
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;

  String? _lastShotPath;

  CaptureMode _mode = CaptureMode.volto;

  final double _targetMmPerPx = 0.117;
  double _ipdMm = 63.0;
  double get _targetPxVolto => _ipdMm / _targetMmPerPx;
  double _lastIpdPx = 0.0;
  bool _scaleOkVolto = false;

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
        (c) => c.lensDirection == CameraLensDirection.back,
      );
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
    if (now.difference(_lastProc).inMilliseconds < 100) return;
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
      if (shown > 0) {
        _lastIpdPx = (_lastIpdPx == 0)
            ? shown
            : (_lastIpdPx * 0.7 + shown * 0.3);
      }
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

  // ====== Scatto + ritorno file ======
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
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      final Size screen = MediaQuery.of(context).size;
      final double shortSideScreen = math.min(screen.width, screen.height);

      double squareSizeScreen;
      if (_lastIpdPx > 0) {
        final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
        final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;
        squareSizeScreen =
            (shortSideScreen / scalaFattore).clamp(32.0, shortSideScreen);
      } else {
        squareSizeScreen = shortSideScreen * 0.70;
      }

      img.Image resized = img.copyResize(original, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

      final String newPath =
          '${Directory.systemTemp.path}/post_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(newPath).writeAsBytes(pngBytes);

      Navigator.pop(context, File(newPath)); // 👈 ritorna solo il file
    } catch (e) {
      debugPrint('Take/save error: $e');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // ====== UI ======
  Widget _buildScaleChip() {
    Color c;
    String text;
    if (_mode == CaptureMode.volto) {
      final double tgt = _targetPxVolto;
      final double minT = tgt * 0.95;
      final double maxT = tgt * 1.05;
      final v = _lastIpdPx;
      if (v == 0) {
        c = Colors.grey;
      } else if (v < minT * 0.9 || v > maxT * 1.1) {
        c = Colors.red;
      } else if (v < minT || v > maxT) {
        c = Colors.amber;
      } else {
        c = Colors.green;
      }
      text = 'Centra il viso – scatta solo col verde';
    } else {
      c = Colors.amber;
      text = 'Particolare – avvicinati e scatta col verde';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1.6),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile'));
    }

    final Size p = ctrl.value.previewSize ?? const Size(1080, 1440);

    final Widget inner = SizedBox(
      width: p.height,
      height: p.width,
      child: CameraPreview(ctrl),
    );

    final Widget previewFull = FittedBox(
      fit: BoxFit.cover,
      child: inner,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: previewFull),
        if (widget.guideImage != null)
          Align(
            alignment: const Alignment(0, -0.3),
            child: SizedBox(
              width: 250,
              height: 250,
              child: Opacity(
                opacity: 0.4,
                child: Image.file(widget.guideImage!, fit: BoxFit.cover),
              ),
            ),
          ),
        Align(
          alignment: const Alignment(0, -0.3),
          child: _buildScaleChip(),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_shooting;
    return SafeArea(
      child: Center(
        child: GestureDetector(
          onTap: canShoot ? _takeAndSavePicture : null,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 3),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildCameraPreview()),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }
}
