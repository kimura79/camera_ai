// 🔹 post_camera_widget.dart — Fotocamera dedicata al POST
//    Versione alleggerita: nessun riferimento a HomePageModel o FFAppState
//    -> Compila senza errori iOS

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:custom_camera_component/pages/distanza_cm_overlay.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:custom_camera_component/models/capture_mode.dart';

// ✅ PAGINA CAMERA PER SCATTO POST
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
  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;

  String? _lastShotPath;

  CaptureMode _mode = CaptureMode.volto;

  // —— parametri scala
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

  // —— face detector
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
      final backIndex =
          _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
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

  // —— stream IPD
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
        _lastIpdPx = (_lastIpdPx == 0) ? shown : (_lastIpdPx * 0.7 + shown * 0.3);
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

    final Size size = Size(image.width.toDouble(), image.height.toDouble());

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: InputImageFormat.yuv420,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ====== Scatto ======
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
      original = img.bakeOrientation(original);

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // crop centrato
      final int minSide = math.min(original.width, original.height);
      int cropSide = minSide;
      int cropX = ((original.width - cropSide) / 2).round();
      int cropY = ((original.height - cropSide) / 2).round();

      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSide,
        height: cropSide,
      );
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (pState.hasAccess) {
        final String baseName = 'post_1024_${DateTime.now().millisecondsSinceEpoch}';
        await PhotoManager.editor.saveImage(pngBytes, filename: '$baseName.png');
      }

      final String outPath = await _tempThumbPath(
        'post_1024_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(outPath).writeAsBytes(pngBytes);
      _lastShotPath = outPath;

      if (mounted) {
        Navigator.pop(context, File(outPath));
      }
    } catch (e) {
      debugPrint('Take/save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio: $e')),
        );
      }
    } finally {
      try {
        if (ctrl.value.isInitialized && !ctrl.value.isStreamingImages) {
          await ctrl.startImageStream(_processCameraImage);
          _streamRunning = true;
        }
      } catch (_) {}
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<String> _tempThumbPath(String fileName) async {
    final dir = await Directory.systemTemp.createTemp('epi_thumbs');
    return '${dir.path}/$fileName';
  }

  // ====== UI ======
  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) return const Center(child: CircularProgressIndicator());
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

        // 👇 Ghost PRE
        if (widget.guideImage != null)
          Center(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Opacity(
                opacity: 0.4,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.file(widget.guideImage!),
                ),
              ),
            ),
          ),

        buildLivellaVerticaleOverlay(),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_shooting;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(width: 54, height: 54),
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              child: SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 6),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: _shooting ? 58 : 64,
                      height: _shooting ? 58 : 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;

    if (state == AppLifecycleState.inactive) {
      try {
        if (_streamRunning) {
          _controller?.stopImageStream();
          _streamRunning = false;
        }
      } catch (_) {}
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameras[_cameraIndex]);
    }
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
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
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

// ✅ Livella verticale
Widget buildLivellaVerticaleOverlay({
  double okThresholdDeg = 1.0,
  double topOffsetPx = 65.0,
}) {
  return Builder(
    builder: (context) {
      final double safeTop = MediaQuery.of(context).padding.top;

      return Positioned(
        top: safeTop + topOffsetPx,
        left: 0,
        right: 0,
        child: Center(
          child: StreamBuilder<AccelerometerEvent>(
            stream: accelerometerEventStream(),
            builder: (context, snap) {
              double angleDeg = 0.0;

              if (snap.hasData) {
                final ax = snap.data!.x;
                final ay = snap.data!.y;
                final az = snap.data!.z;
                final g = math.sqrt(ax * ax + ay * ay + az * az);
                if (g > 0) {
                  double c = (-az) / g;
                  c = c.clamp(-1.0, 1.0);
                  angleDeg = (math.acos(c) * 180.0 / math.pi);
                }
              }

              final bool isOk = (angleDeg - 90.0).abs() <= okThresholdDeg;
              final Color bigColor = isOk ? Colors.greenAccent : Colors.white;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${angleDeg.toStringAsFixed(1)}°",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: bigColor,
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}