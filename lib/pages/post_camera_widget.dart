// 🔹 post_camera_widget.dart — Fotocamera POST semplificata
//    - NIENTE MLKit (fluida)
//    - Ghost PRE a massima larghezza schermo
//    - Riquadro crop 1024x1024
//    - Livella verticale

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👈 immagine PRE da usare come ghost

  const PostCameraWidget({super.key, this.guideImage});

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
      await ctrl.setZoomLevel(1.0);
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
    await old?.dispose();
    await _startController(_cameras[_cameraIndex]);
  }

  // === Scatto + crop 1024 ===
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica fallita');
      original = img.bakeOrientation(original);
      if (isFront) original = img.flipHorizontal(original);

      // Crop quadrato
      final int minSide = math.min(original.width, original.height);
      int cropSide = (minSide * 0.9).round();
      int cropX = ((original.width - cropSide) / 2).round();
      int cropY = ((original.height - cropSide) / 2.2).round(); // alzato un po'

      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSide,
        height: cropSide,
      );
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

      final String outPath =
          '${(await Directory.systemTemp.createTemp()).path}/post_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(pngBytes);
      _lastShotPath = outPath;

      if (mounted) Navigator.pop(context, File(outPath));
    } catch (e) {
      debugPrint('Take/save error: $e');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // === UI ===
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

    final Widget previewFull = FittedBox(fit: BoxFit.cover, child: inner);

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

        // 👇 Ghost PRE: massima larghezza, semi-trasparente
        if (widget.guideImage != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: Image.file(widget.guideImage!, fit: BoxFit.cover),
            ),
          ),

        // 👇 Riquadro target
        Align(
          alignment: const Alignment(0, -0.3),
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green, width: 3),
            ),
          ),
        ),

        // 👇 Livella verticale
        buildLivellaVerticaleOverlay(topOffsetPx: 65.0),
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
            const SizedBox(width: 54, height: 54), // spazio thumbnail
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 6),
                ),
              ),
            ),
            GestureDetector(
              onTap: _switchCamera,
              child: const Icon(Icons.cameraswitch, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
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
            Align(alignment: Alignment.bottomCenter, child: _buildBottomBar()),
          ],
        ),
      ),
    );
  }
}

// === Livella verticale (semplice) ===
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
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isOk ? Colors.greenAccent : Colors.white24),
                ),
                child: Text(
                  "${angleDeg.toStringAsFixed(1)}°",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isOk ? Colors.greenAccent : Colors.white,
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