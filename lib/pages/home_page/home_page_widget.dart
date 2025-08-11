import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:flutter/foundation.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  // Richiesti da FlutterFlow / nav.dart
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
  double _pitchDeg = 0;
  double _rollDeg = 0;
  static const double _levelToleranceDeg = 2.0;

  // Thumbnail
  String? _lastPhotoPath;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras(); // avvio diretto come nei file base → popup permesso
    _listenAccelerometer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) return; // non chiudere durante popup
    if (state == AppLifecycleState.paused) {
      await _controller?.dispose();
      _controller = null;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_controller == null && _cameras.isNotEmpty) {
        await _initController(_cameras[_cameraIndex]);
      }
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        await _initController(_cameras[_cameraIndex]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nessuna fotocamera disponibile')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore inizializzazione camera: $e')),
        );
      }
    }
  }

  Future<void> _initController(CameraDescription description) async {
    final controller = CameraController(
      description,
      defaultTargetPlatform == TargetPlatform.iOS
          ? ResolutionPreset.high
          : ResolutionPreset.max,
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
      final ax = e.x, ay = e.y, az = e.z;
      final roll = math.atan2(ay, az);
      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));
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
      final bytes = await File(xFile.path).readAsBytes();
      final img.Image? raw = img.decodeImage(bytes);
      if (raw == null) throw 'Immagine non valida';

      final int side = math.min(raw.width, raw.height);
      final int left = (raw.width - side) ~/ 2;
      final int top = (raw.height - side) ~/ 2;
      final img.Image cropped = img.copyCrop(raw, x: left, y: top, width: side, height: side);
      final img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);

      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/epidermys_${DateTime.now().millisecondsSinceEpoch}.png';
      final outBytes = img.encodePng(resized);
      final outFile = File(outPath)..writeAsBytesSync(outBytes);

      setState(() => _lastPhotoPath = outFile.path);

      await GallerySaver.saveImage(outFile.path, albumName: 'Epidermys', toDcim: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto salvata nel Rullino')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore scatto: $e')),
        );
      }
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
                  Positioned.fill(
                    child: _FullScreenCameraPreview(controller: controller),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _SquareFramePainter()),
                    ),
                  ),
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
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 24,
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

/// Preview senza distorsione (cover)
class _FullScreenCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _FullScreenCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const Center(child: CircularProgressIndicator());

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

/// Frame guida 1:1
class _SquareFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) * 0.8;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;

    final rect = Rect.fromLTWH(left, top, side, side);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.8);
    canvas.drawRect(rect, paint);

    const corner = 24.0;
    final cw = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;

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

/// Livelle H/V
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

    final rollOk = rollDeg.abs() <= tolDeg;
    final pitchOk = pitchDeg.abs() <= tolDeg;

    final pBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(0.7);
    final pOk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.greenAccent;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-rollDeg * math.pi / 180.0);
    canvas.drawLine(Offset(-lineLen, 0), Offset(lineLen, 0), rollOk ? pOk : pBase);
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawLine(Offset(0, -lineLen), Offset(0, lineLen), pitchOk ? pOk : pBase);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) {
    return old.rollDeg != rollDeg || old.pitchDeg != pitchDeg || old.tolDeg != tolDeg;
  }
}

/// Shutter stile iPhone
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
    const outerSize = 84.0;
    final innerSize = _pressed || widget.isBusy ? 58.0 : 64.0;

    return GestureDetector(
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
            Container(
              width: outerSize,
              height: outerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 6),
              ),
            ),
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