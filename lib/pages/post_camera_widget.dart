// 🔹 post_camera_widget.dart — Fotocamera POST fullscreen con ghost PRE e linee verdi

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
        (c) => c.lensDirection == CameraLensDirection.front,
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

  // ====== Scatto + salvataggio ======
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
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // 🔹 Nessun crop: salva l'immagine originale
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(original));

      final PermissionState pState =
          await PhotoManager.requestPermissionExtend();
      if (!pState.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permesso Foto negato')),
          );
        }
        return;
      }

      final String baseName =
          'post_full_${DateTime.now().millisecondsSinceEpoch}';
      final AssetEntity? asset = await PhotoManager.editor.saveImage(
        pngBytes,
        filename: '$baseName.png',
      );
      if (asset == null) throw Exception('Salvataggio PNG fallito');

      final Directory tempDir = await Directory.systemTemp.createTemp('epi_post');
      final String newPath = '${tempDir.path}/$baseName.png';
      await File(newPath).writeAsBytes(pngBytes);
      _lastShotPath = newPath;

      debugPrint('✅ Foto salvata full-res — ${original.width}x${original.height}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto salvata a pieno schermo')),
        );
        setState(() {});
        Navigator.pop(context, newPath);
      }
    } catch (e) {
      debugPrint('Take/save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // ====== UI Fotocamera ======
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

        // 👻 Ghost PRE (trasparente)
        if (widget.guideImage != null)
          Opacity(
            opacity: 0.4,
            child: Image.file(
              widget.guideImage!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // 🟩 Linee guida verdi (stile Home)
        _buildGridOverlay(),

        // ⚖️ Livella verticale
        buildLivellaVerticaleOverlay(topOffsetPx: 65.0),
      ],
    );
  }

  Widget _buildGridOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final paint = Paint()
          ..color = Colors.greenAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        return CustomPaint(
          size: Size(w, h),
          painter: _GridPainter(paint),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final canShoot = _controller != null &&
        _controller!.value.isInitialized &&
        !_shooting;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Anteprima ultima foto
            GestureDetector(
              onTap: (_lastShotPath != null)
                  ? () async {
                      final p = _lastShotPath!;
                      await showDialog(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.9),
                        builder: (_) => GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: InteractiveViewer(
                            child: Center(child: Image.file(File(p))),
                          ),
                        ),
                      );
                    }
                  : null,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.antiAlias,
                child: (_lastShotPath != null)
                    ? Image.file(File(_lastShotPath!), fit: BoxFit.cover)
                    : const Icon(Icons.image, color: Colors.white70),
              ),
            ),

            // Pulsante scatto
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
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

            // Switch camera
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

// 🎯 Livella verticale
Widget buildLivellaVerticaleOverlay({double okThresholdDeg = 1.0, double topOffsetPx = 65.0}) {
  return Positioned(
    top: topOffsetPx,
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
              angleDeg = (math.acos(c) * 180.0 / math.pi) - 90.0;
            }
          }

          final bool ok = angleDeg.abs() <= okThresholdDeg;
          final Color bigColor = ok ? Colors.greenAccent : Colors.redAccent;

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
}

// 🎯 Pittore griglia verde (stile guida)
class _GridPainter extends CustomPainter {
  final Paint paintStyle;
  _GridPainter(this.paintStyle);

  @override
  void paint(Canvas canvas, Size size) {
    final double stepX = size.width / 3;
    final double stepY = size.height / 3;

    for (int i = 1; i < 3; i++) {
      // linee verticali
      canvas.drawLine(Offset(stepX * i, 0), Offset(stepX * i, size.height), paintStyle);
      // linee orizzontali
      canvas.drawLine(Offset(0, stepY * i), Offset(size.width, stepY * i), paintStyle);
    }

    // bordo esterno
    final border = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
