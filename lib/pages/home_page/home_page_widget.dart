import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:gallery_saver/gallery_saver.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  // 🔗 Richiesti da FlutterFlow / nav.dart
  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;

  // Livelle
  StreamSubscription<AccelerometerEvent>? _accSub;
  double _pitchDeg = 0;   // “verticale”
  double _rollDeg = 0;    // “orizzontale”
  static const double _levelToleranceDeg = 2.0; // soglia “in bolla”

  // Thumbnail
  String? _lastPhotoPath;

  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
    _listenAccelerometer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // Gestisce resume/pause camera su app lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _reinitializeController();
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nessuna fotocamera disponibile')),
          );
        }
        return;
      }
      await _initController(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore inizializzazione camera: $e')),
        );
      }
    }
  }

  Future<void> _reinitializeController() async {
    if (_cameras.isEmpty) return;
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _initController(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) return;

    setState(() {
      _controller?.dispose();
      _controller = controller;
    });
  }

  void _listenAccelerometer() {
    _accSub = accelerometerEvents.listen((e) {
      // Calcolo pitch/roll in gradi “semplici” da accelerometro (feedback livella, non AR).
      final ax = e.x, ay = e.y, az = e.z;
      final roll = math.atan2(ay, az); // orizzontale
      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az)); // verticale

      setState(() {
        _rollDeg = roll * 180.0 / math.pi;
        _pitchDeg = pitch * 180.0 / math.pi;
      });
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _takeSquare1024() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPicture) return;
    setState(() => _isTakingPicture = true);

    try {
      final xFile = await _controller!.takePicture();

      // Carica JPEG in memoria
      final bytes = await File(xFile.path).readAsBytes();
      img.Image? raw = img.decodeImage(bytes);
      if (raw == null) throw 'Immagine non valida';

      // Crop centrale 1:1
      final int side = math.min(raw.width, raw.height);
      final int left = (raw.width - side) ~/ 2;
      final int top = (raw.height - side) ~/ 2;
      final img.Image cropped = img.copyCrop(raw, x: left, y: top, width: side, height: side);

      // Resize a 1024x1024 (senza distorsione)
      final img.Image resized = img.copyResize(
        cropped,
        width: 1024,
        height: 1024,
        interpolation: img.Interpolation.average,
      );

      // Salva su file (PNG per lossless — se vuoi JPEG, cambiamo encoder)
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/epidermys_${DateTime.now().millisecondsSinceEpoch}.png';
      final outBytes = img.encodePng(resized);
      final outFile = File(outPath)..writeAsBytesSync(outBytes);

      setState(() {
        _lastPhotoPath = outFile.path;
      });

      // 👉 Salvataggio AUTOMATICO in galleria (album "Epidermys")
      try {
        final ok = await GallerySaver.saveImage(outFile.path, albumName: 'Epidermys', toDcim: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok == true ? 'Salvata nel Rullino' : 'Impossibile salvare nel Rullino')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore salvataggio galleria: $e')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore scatto: $e')),
      );
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: controller == null || !controller.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // PREVIEW A TUTTO SCHERMO (cover)
                  Positioned.fill(
                    child: _FullScreenCameraPreview(controller: controller),
                  ),

                  // FRAME 1:1 (guida visiva del crop)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SquareFramePainter(),
                      ),
                    ),
                  ),

                  // LIVELLE ORIZZONTALE & VERTICALE
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LevelPainter(
                          rollDeg: _rollDeg,
                          pitchDeg: _pitchDeg,
                          tolDeg: _levelToleranceDeg,
                        ),
                      ),
                    ),
                  ),

                  // TOP BAR (thumbnail, titolo, switch camera)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _lastPhotoPath == null
                            ? const SizedBox(width: 44, height: 44)
                            : _Thumb(path: _lastPhotoPath!),
                        const Text(
                          'Epidermys',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          onPressed: _switchCamera,
                          icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 28),
                          tooltip: 'Cambia fotocamera',
                        ),
                      ],
                    ),
                  ),

                  // BOTTOM: solo shutter stile iPhone
                  Positioned(
                    bottom: MediaReposito ry.of(context).padding.bottom + 24, // typo fixed below
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _IOSShutterButton(
                        isBusy: _isTakingPicture,
                        onTap: _takeSquare1024,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Preview che riempie tutto lo schermo **senza distorcere** (cover).
class _FullScreenCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _FullScreenCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final previewAspect = previewSize.width / previewSize.height;
    final screenAspect = size.width / size.height;

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: screenAspect > previewAspect ? size.width : size.height * previewAspect,
        height: screenAspect > previewAspect ? size.width / previewAspect : size.height,
        child: CameraPreview(controller),
      ),
    );
  }
}

/// Frame quadrato 1:1 centrato (solo guida).
class _SquareFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) * 0.8; // 80% lato schermo
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;

    final rect = Rect.fromLTWH(left, top, side, side);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.8);
    canvas.drawRect(rect, paint);

    // Angoli (stile “L”)
    final corner = 24.0;
    final cw = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;

    // quattro L agli angoli
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + corner, rect.top), cw);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left, rect.top + corner), cw);

    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right - corner, rect.top), cw);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + corner), cw);

    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + corner, rect.bottom), cw);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - corner), cw);

    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right - corner, rect.bottom), cw);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - corner), cw);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Livelle “pittori”: orizzontale (roll) + verticale (pitch).
class _LevelPainter extends CustomPainter {
  final double rollDeg;
  final double pitchDeg;
  final double tolDeg;

  _LevelPainter({
    required this.rollDeg,
    required this.pitchDeg,
    required this.tolDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final lineLen = math.min(size.width, size.height) * 0.35;

    final bool rollOk = rollDeg.abs() <= tolDeg;
    final bool pitchOk = pitchDeg.abs() <= tolDeg;

    final Paint pBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(0.7);

    final Paint pOk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.greenAccent;

    // Orizzontale (ruotata di roll)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-rollDeg * math.pi / 180.0);
    final Paint pH = rollOk ? pOk : pBase;
    canvas.drawLine(Offset(-lineLen, 0), Offset(lineLen, 0), pH);
    canvas.restore();

    // Verticale (feedback colore)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final Paint pV = pitchOk ? pOk : pBase;
    canvas.drawLine(Offset(0, -lineLen), Offset(0, lineLen), pV);
    canvas.restore();

    // Etichetta angoli
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'H ${rollDeg.toStringAsFixed(1)}°  •  V ${pitchDeg.toStringAsFixed(1)}°',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy + lineLen + 12));
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) {
    return old.rollDeg != rollDeg || old.pitchDeg != pitchDeg || old.tolDeg != tolDeg;
  }
}

/// Shutter stile iPhone: anello esterno + cerchio interno animato.
class _IOSShutterButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isBusy;
  const _IOSShutterButton({required this.onTap, required this.isBusy});

  @override
  State<_IOSShutterButton> createState() => _IOSShutterButtonState();
}

class _IOSShutterButtonState extends State<_IOSShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final double outerSize = 84;
    final double innerSize = _pressed || widget.isBusy ? 58 : 64;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.isBusy ? null : widget.onTap,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Anello esterno
            Container(
              width: outerSize,
              height: outerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 6),
              ),
            ),
            // Cerchio interno (animato)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isBusy ? Colors.white24 : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isBusy;
  const _ShutterButton({required this.onTap, required this.isBusy});

  @override
  Widget build(BuildContext context) {
    // Non usato più (lasciato se vuoi tornare allo stile precedente)
    return const SizedBox.shrink();
  }
}

class _Thumb extends StatelessWidget {
  final String path;
  const _Thumb({required this.path});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.9),
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}