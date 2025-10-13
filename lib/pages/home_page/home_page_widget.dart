// 🔹 home_page_widget.dart — Fotocamera fullscreen (foto identica alla preview) + livella verticale

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:custom_camera_component/pages/analysis_preview.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:custom_camera_component/pages/distanza_cm_overlay.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';


// ✅ Pagina risultati analisi
class AnalysisResultsPage extends StatelessWidget {
  final String baseImagePath;
  final String macchieOverlayPath;
  final String rugheOverlayPath;

  const AnalysisResultsPage({
    super.key,
    required this.baseImagePath,
    required this.macchieOverlayPath,
    required this.rugheOverlayPath,
  });

  Widget _buildResultItem({
    required String title,
    required String overlayPath,
    required String scaleText,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Image.file(
          File(overlayPath),
          width: 300,
          height: 300,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            scaleText,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Risultati Analisi"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildResultItem(
              title: "Macchie Cutanee",
              overlayPath: macchieOverlayPath,
              scaleText: "Scala di giudizio: Lieve → Grave",
              color: Colors.orangeAccent,
            ),
            _buildResultItem(
              title: "Rughe",
              overlayPath: rugheOverlayPath,
              scaleText: "Scala di giudizio: Superficiale → Profonda",
              color: Colors.cyanAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class HomePageWidget extends StatefulWidget {
  final File? guideImage;

  const HomePageWidget({super.key, this.guideImage});

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
  CaptureMode _mode = CaptureMode.volto;

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
      ResolutionPreset.max, // usa la massima risoluzione disponibile
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

  // ====== Scatto e salvataggio (foto identica alla preview fullscreen) ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      final XFile shot = await ctrl.takePicture();

      // Decodifica immagine originale
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // 🔹 CROP per far combaciare la foto con la preview fullscreen
      final Size screen = MediaQuery.of(context).size;
      final double screenAspect = screen.width / screen.height;
      final double photoAspect = original.width / original.height;

      if ((photoAspect - screenAspect).abs() > 0.01) {
        int newWidth, newHeight, offsetX, offsetY;

        if (photoAspect > screenAspect) {
          // Foto più larga → ritaglia ai lati
          newWidth = (original.height * screenAspect).round();
          newHeight = original.height;
          offsetX = ((original.width - newWidth) / 2).round();
          offsetY = 0;
        } else {
          // Foto più stretta → ritaglia sopra/sotto
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

      // 🔹 Salva PNG lossless
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(original));

      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (!pState.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permesso Foto negato')),
          );
        }
        return;
      }

      final String baseName =
          'volto_full_${DateTime.now().millisecondsSinceEpoch}.png';

      final AssetEntity? asset =
          await PhotoManager.editor.saveImage(pngBytes, filename: baseName);
      if (asset == null) throw Exception('Salvataggio PNG fallito');

      final String newPath = (await _tempThumbPath(baseName));
      await File(newPath).writeAsBytes(pngBytes);
      _lastShotPath = newPath;

      debugPrint(
          '✅ Foto salvata — risoluzione: ${original.width}x${original.height} (match preview)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Foto salvata identica alla preview fullscreen')),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnalysisPreview(
              imagePath: newPath,
              mode: "fullface",
            ),
          ),
        ).then((analyzed) {
          if (analyzed != null) {
            Navigator.pop(context);
            Navigator.pop(context, analyzed);
          }
        });
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

  Future<String> _tempThumbPath(String fileName) async {
    final dir = await Directory.systemTemp.createTemp('epi_full');
    return '${dir.path}/$fileName';
  }

  // ====== Anteprima camera fullscreen ======
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

    final Widget previewFull = FittedBox(fit: BoxFit.cover, child: inner);

    return needsMirror
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
            child: previewFull,
          )
        : previewFull;
  }

  // ====== Barra inferiore ======
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
            // Thumbnail ultima foto
            GestureDetector(
              onTap: (_lastShotPath != null)
                  ? () async {
                      final p = _lastShotPath!;
                      await showDialog(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.9),
                        builder: (_) => GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child:
                              InteractiveViewer(child: Center(child: Image.file(File(p)))),
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
            // ✅ Anteprima fotocamera fullscreen
            Positioned.fill(child: _buildCameraPreview()),

                // 🔹 Livella orizzontale centrata — 3 linee
    Positioned.fill(
      child: StreamBuilder<GyroscopeEvent>(
        stream: gyroscopeEvents,
        builder: (context, snapshot) {
          double rollDeg = 0.0;
          if (snapshot.hasData) {
            final gx = snapshot.data!.x;
            final gy = snapshot.data!.y;
            final gz = snapshot.data!.z;
            rollDeg = gx * 57.3; // conversione rad → gradi (approssimativa)
          }
          return Center(
            child: LivellaOrizzontale3Linee(
              width: MediaQuery.of(context).size.width * 0.6,
              height: 100,
              rollDeg: rollDeg,
            ),
          );
        },
      ),
    ),

             // ✅ Sagoma ovale verde (nuova)
             const FaceGuideOverlay(),

             // ✅ Livella verticale (ora disegnata sopra il nero)
             buildLivellaVerticaleOverlay(mode: _mode, topOffsetPx: 90.0),

            // ✅ Testo guida sopra l’ovale
            Positioned(
              top: MediaQuery.of(context).size.height * 0.1,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "Posiziona il volto all’interno dell’ovale",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ✅ Barra inferiore
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

Widget buildLivellaVerticaleOverlay({
  CaptureMode? mode,
  double okThresholdDeg = 1.0,
  double topOffsetPx = 65.0,
}) {
  if (mode != null && mode != CaptureMode.volto) {
    return const SizedBox.shrink();
  }

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
                  angleDeg = (math.acos(c) * 180.0 / math.pi) - 90.0;
                }
              }

              final bool ok = angleDeg.abs() <= okThresholdDeg;
              final Color bigColor =
                  ok ? Colors.greenAccent : Colors.redAccent;

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
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
// ==========================================================
// 🔹 SAGOMA OVALE VERDE — GUIDA INQUADRATURA VOLTO
// ==========================================================
class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _FaceGuidePainter(),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintOverlay = Paint()
      ..color = Colors.black.withOpacity(0.75)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
  center: Offset(size.width / 2, size.height * 0.52),
  width: size.width * 0.95, // più largo
  height: size.height * 0.70, // meno alto
);

    // 🔹 Crea il buco ovale nel layer nero
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addOval(ovalRect),
    );

    canvas.drawPath(path, paintOverlay);

    // 🔹 Bordo verde
    final paintBorder = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, paintBorder);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ==========================================================
// 🔹 LIVELLA ORIZZONTALE A 3 LINEE (fullscreen, scala 0.117)
// ==========================================================

class LivellaOrizzontale3Linee extends StatelessWidget {
  final double width;
  final double height;
  final double rollDeg;
  final double okThresholdDeg;

  const LivellaOrizzontale3Linee({
    super.key,
    required this.width,
    required this.height,
    required this.rollDeg,
    this.okThresholdDeg = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final isOk = rollDeg.abs() < okThresholdDeg;

    return Transform.rotate(
      angle: -rollDeg * math.pi / 180,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _LivellaPainter(isOk: isOk),
        ),
      ),
    );
  }
}

class _LivellaPainter extends CustomPainter {
  final bool isOk;

  _LivellaPainter({required this.isOk});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isOk ? Colors.green : Colors.red
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final spacing = size.height / 4;

    // Disegna 3 linee orizzontali centrate
    for (int i = -1; i <= 1; i++) {
      final y = centerY + i * spacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LivellaPainter oldDelegate) {
    return oldDelegate.isOk != isOk;
  }
}





