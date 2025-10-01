// 🔹 post_camera_widget.dart — Fotocamera POST
//    - Ghost PRE quadrato a tutta larghezza
//    - Livella verticale
//    - Crop esatto dal quadrato verde 1024x1024
//    - NIENTE MLKit

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👈 immagine PRE come ghost

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
  double _lastSquareSize = 0; // 👈 memorizziamo il lato del quadrato verde
  double _lastDx = 0;         // offset per mapping
  double _lastDy = 0;
  double _lastScale = 1;

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
      imageFormatGroup: ImageFormatGroup.jpeg,
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

  // ====== Scatto + crop dal quadrato verde ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      // 1) Scatta
      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();

      // 2) Decodifica
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // 3) Calcola mapping quadrato verde -> pixel immagine
      final Size p = ctrl.value.previewSize ?? const Size(1080, 1440);
      final double previewW = p.height.toDouble();
      final double previewH = p.width.toDouble();

      final Size screen = MediaQuery.of(context).size;
      final double screenW = screen.width;
      final double screenH = screen.height;

      final double scale = math.max(screenW / previewW, screenH / previewH);
      final double dispW = previewW * scale;
      final double dispH = previewH * scale;
      final double dx = (screenW - dispW) / 2.0;
      final double dy = (screenH - dispH) / 2.0;

      final double squareSizeScreen = _lastSquareSize > 0
          ? _lastSquareSize
          : math.min(screenW, screenH); // fallback

      final double leftScreen = (screenW - squareSizeScreen) / 2.0;
      final double topScreen = (screenH - squareSizeScreen) / 2.0;

      final double leftInShown = leftScreen - dx;
      final double topInShown = topScreen - dy;

      final double leftPreview = leftInShown / scale;
      final double topPreview = topInShown / scale;
      final double sidePreview = squareSizeScreen / scale;

      final double ratioX = original.width / previewW;
      final double ratioY = original.height / previewH;

      int cropX = (leftPreview * ratioX).round();
      int cropY = (topPreview * ratioY).round();
      int cropSide = (sidePreview * math.min(ratioX, ratioY)).round();

      cropSide =
          cropSide.clamp(1, math.min(original.width, original.height));
      cropX = cropX.clamp(0, original.width - cropSide);
      cropY = cropY.clamp(0, original.height - cropSide);

      // 4) Crop preciso del quadrato verde
      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSide,
        height: cropSide,
      );

      // 5) Resize 1024x1024
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

      // 6) Salva
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
    } finally {
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
        final double squareSize = screenW; // 👈 quadrato verde max larghezza
        _lastSquareSize = squareSize;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: previewFull),

            if (widget.guideImage != null)
              Center(
                child: SizedBox(
                  width: squareSize,
                  height: squareSize,
                  child: Opacity(
                    opacity: 0.35,
                    child: Image.file(widget.guideImage!, fit: BoxFit.cover),
                  ),
                ),
              ),

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
            const SizedBox(width: 54, height: 54),
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              child: Container(
                width: 78,
                height: 78,
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameras[_cameraIndex]);
    }
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

// ====== Livella verticale ======
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
              final String badgeTxt = isOk ? "OK" : "Inclina";

              return Column(
                children: [
                  Text("${angleDeg.toStringAsFixed(1)}°",
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: bigColor)),
                  Text(badgeTxt,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}