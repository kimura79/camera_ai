// 📂 lib/pages/pre_post/pre_post_widget.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../analysis_preview.dart';
import '../distanza_cm_overlay.dart';
import '../level_guide.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '../home_page/home_page_model.dart';
export '../home_page/home_page_model.dart';

// 🔹 Widget principale PRE/POST
class PrePostWidget extends StatefulWidget {
  final String? preFile;   // Filename analisi PRE nel DB
  final String? postFile;  // Filename analisi POST nel DB
  final String? guideImage; // immagine guida PRE

  const PrePostWidget({
    super.key,
    this.preFile,
    this.postFile,
    this.guideImage,
  });

  @override
  State<PrePostWidget> createState() => _PrePostWidgetState();
}

class _PrePostWidgetState extends State<PrePostWidget> {
  File? preImage;
  File? postImage;
  Map<String, dynamic>? compareData;

  String? preFile;
  String? postFile;

  @override
  void initState() {
    super.initState();
    preFile = widget.preFile;
    postFile = widget.postFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CameraOverlayPage(guideImage: widget.guideImage),
    );
  }
}

// 🔹 Enum per modalità scatto
enum CaptureMode { volto, particolare }

// 🔹 Pagina fotocamera con overlay PRE
class CameraOverlayPage extends StatefulWidget {
  final String? guideImage;

  const CameraOverlayPage({super.key, this.guideImage});

  @override
  State<CameraOverlayPage> createState() => _CameraOverlayPageState();
}

class _CameraOverlayPageState extends State<CameraOverlayPage>
    with WidgetsBindingObserver {
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

  static const double _targetMmPart = 120.0;
  double get _targetPxPart => _targetMmPart / _targetMmPerPx;

  bool get _scaleOkPart {
    if (_lastIpdPx <= 0) return false;
    final mmPerPxAttuale = _ipdMm / _lastIpdPx;
    final larghezzaRealeMm = mmPerPxAttuale * 1024.0;
    final distanzaCm = (larghezzaRealeMm / 10.0) * 2.0;
    return (distanzaCm >= 11.0 && distanzaCm <= 13.0);
  }

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

  // ====== Scatto e navigazione ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      if (_streamRunning) {
        await ctrl.stopImageStream();
        _streamRunning = false;
      }

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      final pngBytes = Uint8List.fromList(img.encodePng(original));

      final PermissionState pState =
          await PhotoManager.requestPermissionExtend();
      if (!pState.hasAccess) return;

      final String baseName =
          'prepost_${DateTime.now().millisecondsSinceEpoch}';
      final AssetEntity? asset = await PhotoManager.editor.saveImage(
        pngBytes,
        filename: '$baseName.png',
      );
      if (asset == null) throw Exception('Salvataggio PNG fallito');

      final String newPath = (await _tempThumbPath('$baseName.png'));
      await File(newPath).writeAsBytes(pngBytes);
      _lastShotPath = newPath;

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnalysisPreview(
              imagePath: newPath,
              mode: _mode == CaptureMode.particolare ? "particolare" : "fullface",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Take/save error: $e');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<String> _tempThumbPath(String fileName) async {
    final dir = await Directory.systemTemp.createTemp('epi_thumbs');
    return '${dir.path}/$fileName';
  }

  // ====== UI PREVIEW ======
  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile'));
    }

    final bool isFront =
        ctrl.description.lensDirection == CameraLensDirection.front;
    final bool needsMirror = isFront && Platform.isAndroid;

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

    final Widget preview = needsMirror
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
            child: previewFull,
          )
        : previewFull;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: preview),
        if (widget.guideImage != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.25,
              child: Image.asset(widget.guideImage!, fit: BoxFit.cover),
            ),
          ),
        buildDistanzaCmOverlay(
          ipdPx: _lastIpdPx,
          ipdMm: _ipdMm,
          targetMmPerPx: _targetMmPerPx,
          alignY: -0.05,
          mode: _mode == CaptureMode.particolare ? "particolare" : "fullface",
          isFrontCamera: isFront,
        ),
        buildLivellaVerticaleOverlay(
          mode: _mode,
          topOffsetPx: 65.0,
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_streamRunning) {
        _controller?.stopImageStream();
      }
    } catch (_) {}
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(child: _buildCameraPreview()),
            Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: _shooting ? null : _takeAndSavePicture,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}