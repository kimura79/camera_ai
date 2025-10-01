// 🔹 post_camera_widget.dart — Fotocamera POST minimal
//    Solo: preview camera + ghost Pre guida quadrato max + livella verticale

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/index.dart';
import 'home_page/home_page_model.dart';
export 'home_page/home_page_model.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // immagine PRE come ghost guida

  const PostCameraWidget({super.key, this.guideImage});

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
      debugPrint("Camera init error: $e");
      setState(() => _initializing = false);
    }
  }

  Future<void> _startController(CameraDescription desc) async {
    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      debugPrint("Controller error: $e");
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

  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;
    setState(() => _shooting = true);
    try {
      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception("Decodifica immagine fallita");

      // crop quadrato massimo (lato corto)
      final int side = math.min(original.width, original.height);
      final int offsetX = ((original.width - side) / 2).round();
      final int offsetY = ((original.height - side) / 2).round();
      img.Image cropped = img.copyCrop(original,
          x: offsetX, y: offsetY, width: side, height: side);

      // resize a 1024x1024
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (pState.hasAccess) {
        final String baseName =
            'post_1024_${DateTime.now().millisecondsSinceEpoch}';
        await PhotoManager.editor.saveImage(pngBytes, filename: "$baseName.png");
      }

      final String outPath = await _tempThumbPath(
          "post_1024_${DateTime.now().millisecondsSinceEpoch}.png");
      await File(outPath).writeAsBytes(pngBytes);
      _lastShotPath = outPath;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Foto POST 1024×1024 salvata")),
        );
        Navigator.pop(context, File(outPath)); // torna al PrePost
      }
    } catch (e) {
      debugPrint("Take error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore salvataggio: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<String> _tempThumbPath(String fileName) async {
    final dir = await Directory.systemTemp.createTemp('epi_thumbs');
    return '${dir.path}/$fileName';
  }

  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text("Fotocamera non disponibile"));
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;
        final double squareSize = math.min(screenW, screenH);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: previewFull),

            // 👻 ghost PRE guida quadrata
            if (widget.guideImage != null)
              Center(
                child: SizedBox(
                  width: squareSize,
                  height: squareSize,
                  child: Opacity(
                    opacity: 0.4,
                    child: Image.file(widget.guideImage!, fit: BoxFit.cover),
                  ),
                ),
              ),

            // Riquadro quadrato
            Center(
              child: Container(
                width: squareSize,
                height: squareSize,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 4),
                ),
              ),
            ),
          ],
        );
      },
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
            Container(width: 54, height: 54), // placeholder vuoto
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 6),
                ),
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
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
  void dispose() {
    _model.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(child: _buildCameraPreview()),
            buildLivellaVerticaleOverlay(topOffsetPx: 65.0),
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

// ————————————————————————————————————————
// Livella verticale
// ————————————————————————————————————————
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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