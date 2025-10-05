import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:sensors_plus/sensors_plus.dart';

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
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  bool _initializing = true;
  bool _shooting = false;
  String? _lastShotPath;
  CaptureMode _mode = CaptureMode.volto;

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
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _controller =
          CameraController(back, ResolutionPreset.max, enableAudio: false);
      await _controller!.initialize();
      setState(() => _initializing = false);
    } catch (e) {
      debugPrint("Errore init camera: $e");
      setState(() => _initializing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final newIndex =
        (_cameras.indexOf(_controller!.description) + 1) % _cameras.length;
    final newDesc = _cameras[newIndex];
    await _controller?.dispose();
    _controller =
        CameraController(newDesc, ResolutionPreset.max, enableAudio: false);
    await _controller!.initialize();
    setState(() {});
  }

  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;
    setState(() => _shooting = true);
    try {
      final XFile shot = await ctrl.takePicture();
      final bytes = await File(shot.path).readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception("Immagine non valida");

      // Crop centrale 1:1 e resize 1024×1024
      final int side = math.min(decoded.width, decoded.height);
      final int x = ((decoded.width - side) / 2).round();
      final int y = ((decoded.height - side) / 2).round();
      final img.Image cropped =
          img.copyCrop(decoded, x: x, y: y, width: side, height: side);
      final img.Image resized =
          img.copyResize(cropped, width: 1024, height: 1024);

      final Uint8List png = Uint8List.fromList(img.encodePng(resized));
      final String name = "foto_${DateTime.now().millisecondsSinceEpoch}.png";

      final PermissionState p = await PhotoManager.requestPermissionExtend();
      if (!p.hasAccess) throw Exception("Permesso foto negato");
      await PhotoManager.editor.saveImage(png, filename: name);

      final dir = await Directory.systemTemp.createTemp('epi_temp');
      final pathLocal = path.join(dir.path, name);
      await File(pathLocal).writeAsBytes(png);
      _lastShotPath = pathLocal;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Foto salvata 1024×1024")),
        );
      }
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Widget _buildCameraPreview() {
    if (_initializing) return const Center(child: CircularProgressIndicator());
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text("Fotocamera non disponibile"));
    }

    final preview = CameraPreview(ctrl);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;

        // quadrato che tocca i bordi laterali (1:1)
        final double squareSize = screenW;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.previewSize!.height,
                  height: ctrl.value.previewSize!.width,
                  child: preview,
                ),
              ),
            ),

            // Quadrato fisso (tocca bordi laterali) alzato del 30%
            Align(
              alignment: const Alignment(0, -0.3),
              child: Container(
                width: squareSize,
                height: squareSize,
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.white, width: 4)),
                child: _mode == CaptureMode.volto
                    ? CustomPaint(painter: _OvalPainter(squareSize))
                    : null,
              ),
            ),

            _buildLivellaVerticaleOverlay(),

            Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(child: _buildModeSelector()),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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

                    GestureDetector(
                      onTap: _shooting ? null : _takeAndSavePicture,
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 6),
                          color: Colors.white.withOpacity(0.1),
                        ),
                        child: Center(
                          child: Container(
                            width: _shooting ? 58 : 64,
                            height: _shooting ? 58 : 64,
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
                        child:
                            const Icon(Icons.cameraswitch, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModeSelector() {
    Widget chip(String text, CaptureMode value) {
      final bool selected = _mode == value;
      return GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: 1.2,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip('VOLTO', CaptureMode.volto),
        const SizedBox(width: 10),
        chip('PARTICOLARE', CaptureMode.particolare),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildCameraPreview()),
    );
  }
}

class _OvalPainter extends CustomPainter {
  final double squareSize;
  _OvalPainter(this.squareSize);

  @override
  void paint(Canvas canvas, Size size) {
    // Pittura per contorno ovale
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withOpacity(0.95)
      ..strokeWidth = 3.5;

    // Pittura per asse centrale
    final Paint axis = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 2;

    // 🔹 Ovale più stretto (simile a volto umano)
    // larghezza ridotta al 70% invece di 83%
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: squareSize * 0.70,
      height: squareSize,
    );

    // Disegna ovale
    canvas.drawOval(rect, outline);

    // 🔹 Linea verticale centrale
    final double centerX = size.width / 2;
    canvas.drawLine(
      Offset(centerX, rect.top),
      Offset(centerX, rect.bottom),
      axis,
    );

    // 🔹 (Facoltativo) cerchietto centrale piccolo
    final Paint centerDot = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, size.height / 2), 3, centerDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _buildLivellaVerticaleOverlay({
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
              final Color badgeBg =
                  isOk ? Colors.green.withOpacity(0.85) : Colors.black54;
              final Color badgeBor =
                  isOk ? Colors.greenAccent : Colors.white24;
              final String badgeTxt = isOk ? "OK" : "Inclina";

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: badgeBor, width: 1.2),
                    ),
                    child: Text(
                      badgeTxt,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}