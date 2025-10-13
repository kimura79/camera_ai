// 🔹 home_page_widget.dart — Fotocamera fullscreen (foto identica alla preview) + livella verticale

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

            // ✅ Livella verticale
            buildLivellaVerticaleOverlay(mode: _mode, topOffsetPx: 65.0),

            // ✅ Sagoma ovale verde (nuova)
            const FaceGuideOverlay(),

            // ✅ Livella orizzontale
            const LevelGuide(),

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
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.8, // 80% larghezza schermo
      height: size.height * 0.9, // quasi piena altezza
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
// 🔹 LIVELLA ORIZZONTALE STILE iOS (3 LINEE)
// ==========================================================
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LevelGuide extends StatefulWidget {
  const LevelGuide({super.key});

  @override
  State<LevelGuide> createState() => _LevelGuideState();
}

class _LevelGuideState extends State<LevelGuide> {
  StreamSubscription? _accSub;

  double _rollDeg = 0;
  double _pitchDeg = 0;
  double _rollFilt = 0;
  double _pitchFilt = 0;

  static const _alpha = 0.12;

  @override
  void initState() {
    super.initState();
    _accSub = accelerometerEventStream().listen(_onAccelerometer);
  }

  @override
  void dispose() {
    _accSub?.cancel();
    super.dispose();
  }

  void _onAccelerometer(AccelerometerEvent e) {
    final rollRad = math.atan2(e.y, e.z);
    final pitchRad = math.atan2(-e.x, math.sqrt(e.y * e.y + e.z * e.z));

    final roll = rollRad * 180 / math.pi;
    final pitch = pitchRad * 180 / math.pi;

    _rollFilt = _rollFilt + _alpha * (roll - _rollFilt);
    _pitchFilt = _pitchFilt + _alpha * (pitch - _pitchFilt);

    setState(() {
      _rollDeg = _rollFilt;
      _pitchDeg = _pitchFilt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rollErr = _rollDeg;
    final pitchOk = _pitchDeg.abs() <= 3.0;

    double offset = (rollErr.abs() * 2.0).clamp(0, 28.0);
    final aligned = rollErr.abs() <= 1.0 && pitchOk;
    if (aligned) offset = 0;

    final baseColor = Colors.white.withOpacity(0.9);
    final okColor = Colors.greenAccent.withOpacity(0.95);

    final thick = aligned ? 3.5 : 2.0;

    return IgnorePointer(
      ignoring: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final centerY = c.maxHeight / 2;
          final lineWidth = c.maxWidth * 0.5;
          final x = (c.maxWidth - lineWidth) / 2;

          return Stack(
            children: [
              Positioned(
                left: x,
                top: centerY,
                child: _Line(
                  width: lineWidth,
                  thickness: thick,
                  color: aligned ? okColor : baseColor.withOpacity(0.55),
                ),
              ),
              Positioned(
                left: x,
                top: centerY - offset,
                child: _Line(
                  width: lineWidth,
                  thickness: 2.0,
                  color: aligned ? Colors.transparent : baseColor,
                ),
              ),
              Positioned(
                left: x,
                top: centerY + offset,
                child: _Line(
                  width: lineWidth,
                  thickness: 2.0,
                  color: aligned ? Colors.transparent : baseColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final double width;
  final double thickness;
  final Color color;
  const _Line({required this.width, required this.thickness, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: thickness,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

