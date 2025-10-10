// 🔹 post_camera_widget.dart — Fotocamera POST fullscreen identica a Home + ghost grigio con linee verdi Sobel

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👻 immagine PRE come ghost

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

// 👻 Ghost grigio chiaro + linee verdi effetto "Canny soft" (Flutter safe)
Future<Uint8List> _processGhostWithLines(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    // 1️⃣ Scala di grigi + schiarimento + contrasto
    final gray = img.grayscale(decoded);
    final bright = img.adjustColor(
      gray,
      brightness: 0.3,
      contrast: 1.4,
      saturation: 0,
    );

    // 2️⃣ Rilevamento bordi (Sobel = compatibile con Flutter)
    final edges = img.sobel(bright);

    // 3️⃣ Overlay verde sulle linee
    final greenOverlay = img.Image.from(bright);
    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final px = edges.getPixel(x, y);
        final lum = img.getLuminanceRgb(px.r, px.g, px.b);
        if (lum > 35) { // soglia più bassa = più dettagli visibili
          greenOverlay.setPixel(x, y, img.ColorInt32.rgb(0, 255, 100));
        }
      }
    }

    // 4️⃣ Fusione "manuale" ghost + verde (equivalente a alphaComposite)
    final blended = img.Image.from(bright);
    for (int y = 0; y < bright.height; y++) {
      for (int x = 0; x < bright.width; x++) {
        final basePx = bright.getPixel(x, y);
        final overlayPx = greenOverlay.getPixel(x, y);

        // blending manuale (55% overlay, 45% base)
        final r = ((basePx.r * 0.45) + (overlayPx.r * 0.55)).toInt().clamp(0, 255);
        final g = ((basePx.g * 0.45) + (overlayPx.g * 0.55)).toInt().clamp(0, 255);
        final b = ((basePx.b * 0.45) + (overlayPx.b * 0.55)).toInt().clamp(0, 255);

        blended.setPixel(x, y, img.ColorInt32.rgb(r, g, b));
      }
    }

    return Uint8List.fromList(img.encodePng(blended));
  } catch (e) {
    debugPrint("Ghost processing error: $e");
    return file.readAsBytes();
  }
}
  
  // ====== Scatto foto identico alla preview fullscreen ======
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

      // === Allinea l'immagine all'aspect ratio dello schermo ===
      final Size screen = MediaQuery.of(context).size;
      final double screenAspect = screen.width / screen.height;
      final double photoAspect = original.width / original.height;

      if ((photoAspect - screenAspect).abs() > 0.01) {
        int newWidth, newHeight, offsetX, offsetY;
        if (photoAspect > screenAspect) {
          // foto più larga → taglia ai lati
          newWidth = (original.height * screenAspect).round();
          newHeight = original.height;
          offsetX = ((original.width - newWidth) / 2).round();
          offsetY = 0;
        } else {
          // foto più stretta → taglia sopra/sotto
          newWidth = original.width;
          newHeight = (original.width / screenAspect).round();
          offsetX = 0;
          offsetY = ((original.height - newHeight) / 2).round();
        }
        original = img.copyCrop(
          original,
          x: offsetX,
          y: offsetY,
          width: newWidth,
          height: newHeight,
        );
      }

      // === Salva immagine finale ===
      final Uint8List jpgBytes =
          Uint8List.fromList(img.encodeJpg(original, quality: 95));

      final PermissionState perm = await PhotoManager.requestPermissionExtend();
      if (perm.hasAccess) {
        final String baseName = 'post_full_${DateTime.now().millisecondsSinceEpoch}';
        await PhotoManager.editor.saveImage(jpgBytes, filename: '$baseName.jpg');
      }

      final dir = await Directory.systemTemp.createTemp('epi_post');
      final String outPath =
          '${dir.path}/post_full_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpgBytes);
      _lastShotPath = outPath;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto POST salvata identica alla preview')),
        );
        Navigator.pop(context, File(outPath));
      }
    } catch (e) {
      debugPrint('Errore scatto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // ====== Preview FULLSCREEN + ghost ======
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

        // 👻 Ghost PRE sovrapposto a piena grandezza
        if (widget.guideImage != null)
          FutureBuilder(
            future: _processGhostWithLines(widget.guideImage!),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox();
              }
              if (!snapshot.hasData) return const SizedBox();
              return Opacity(
                opacity: 0.55,
                child: Image.memory(
                  snapshot.data as Uint8List,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              );
            },
          ),

        // ⚖️ Livella verticale
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

            // 🔘 Pulsante scatto
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

// ⚖️ Livella verticale
Widget buildLivellaVerticaleOverlay({
  double okThresholdDeg = 1.5,
  double topOffsetPx = 65.0,
}) {
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

          final bool isOk = angleDeg.abs() <= okThresholdDeg;
          final Color bigColor = isOk ? Colors.greenAccent : Colors.white;

          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${angleDeg.abs().toStringAsFixed(1)}°",
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
