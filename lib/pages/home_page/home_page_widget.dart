// 🔹 home_page_widget.dart — Due TAB separati: VOLTO e PARTICOLARE
// Entrambe le tab calibrano con occhi (IPD=63mm). Scala target 0.117 mm/px (≈12 cm in 1024).
// Bordi spessi, offset riquadro -0.3, crop identico alla preview (anche reverse camera).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum CaptureMode { volto, particolare }

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});
  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  // ===== Camera =====
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;

  // ===== Modalità =====
  CaptureMode _mode = CaptureMode.volto;

  // ===== Scala / UI =====
  static const double _targetMmPerPx = 0.117; // 12 cm in 1024 px
  static const double _offsetFactorY = -0.3;  // riquadro alzato del 30%
  static const double _tolerance = 0.05;      // ±5%
  static const double _frameThickness = 8.0;  // bordo riquadro spesso
  static const double _badgeBorder = 3.0;     // bordo badge

  // IPD virtuale fisso
  static const double _ipdMm = 63.0;
  double _lastIpdPx = 0.0;            // misurazione IPD corrente (px) dalla preview
  DateTime _lastFaceSeen = DateTime.fromMillisecondsSinceEpoch(0);

  // Lock della calibrazione riusabile tra tab
  bool _locked = false;
  double? _lockedMmPerPx;

  // Helpers di scala
  bool get _hasRecentFace =>
      DateTime.now().difference(_lastFaceSeen).inMilliseconds < 1200;
  bool get _hasCalibration => _lockedMmPerPx != null;

  double? get _mmPerPxAttuale {
    if (_hasCalibration) return _lockedMmPerPx;
    if (_lastIpdPx > 0 && _hasRecentFace) return _ipdMm / _lastIpdPx;
    return null;
  }

  bool get _scaleOk {
    final m = _mmPerPxAttuale;
    if (m == null) return false;
    return ((m - _targetMmPerPx).abs() / _targetMmPerPx) <= _tolerance;
    // verde quando ±5%
  }

  // ===== ML Kit =====
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);
  bool _streamRunning = false;

  // ===== Init =====
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
      // Preferisci back se presente
      final backIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
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
      await ctrl.setZoomLevel(1.0); // 🔒 niente zoom variabile
      await ctrl.startImageStream(_processCameraImage);
      _streamRunning = true;

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
    try {
      if (_streamRunning) {
        await old?.stopImageStream();
        _streamRunning = false;
      }
    } catch (_) {}
    await old?.dispose();
    await _startController(_cameras[_cameraIndex]);
  }

  // ===== Preview stream → ML Kit in entrambe le TAB =====
  Future<void> _processCameraImage(CameraImage image) async {
    // In entrambe le modalità cerchiamo gli occhi per poter calibrare.
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 250) return;
    _lastProc = now;

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      final rotation = _rotationFromSensor(ctrl.description.sensorOrientation);
      final inputImage = _inputImageFromCameraImage(image, rotation);

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        if (!_locked) {
          setState(() {
            _lastIpdPx = 0.0;
          });
        }
        return;
      }
      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        if (!_locked) {
          setState(() {
            _lastIpdPx = 0.0;
          });
        }
        return;
      }
      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      // aggiorna misura e last seen
      setState(() {
        _lastIpdPx = distPx;
        _lastFaceSeen = DateTime.now();
      });

      // blocco auto (0.6s stabili in range) — se vuoi evitare, commenta questa parte
      final mmPerPx = _ipdMm / distPx;
      final inRange =
          ((mmPerPx - _targetMmPerPx).abs() / _targetMmPerPx) <= _tolerance;

      if (!_locked && inRange) {
        // usa una piccola finestra: se rimane in range per 0.6s, blocca
        _lockCandidateStart ??= DateTime.now();
        if (DateTime.now()
                .difference(_lockCandidateStart!)
                .inMilliseconds >=
            600) {
          setState(() {
            _locked = true;
            _lockedMmPerPx = mmPerPx;
          });
          // reset finestra
          _lockCandidateStart = null;
        }
      } else {
        _lockCandidateStart = null;
      }
    } catch (e) {
      // ignora errori sporadici in preview
    }
  }

  DateTime? _lockCandidateStart;

  // ===== Helpers ML Kit =====
  InputImageRotation _rotationFromSensor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _inputImageFromCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final b = BytesBuilder(copy: false);
    for (final Plane plane in image.planes) {
      b.add(plane.bytes);
    }
    final Uint8List bytes = b.toBytes();

    final Size size = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: InputImageFormat.yuv420,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ===== Scatto + crop identico al riquadro =====
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    // In particolare: se non c'è calibrazione attiva, richiedi occhi
    if (_mode == CaptureMode.particolare && _mmPerPxAttuale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mostra gli occhi 1s per calibrare (63 mm), poi avvicinati al particolare.'),
        ),
      );
      return;
    }

    setState(() => _shooting = true);
    try {
      if (_streamRunning) {
        await ctrl.stopImageStream();
        _streamRunning = false;
      }

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      final img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      // === Calcolo crop coerente con overlay ===
      // mm/px attuale (da lock o da IPD recente)
      final double? mmPerPx = _mmPerPxAttuale;

      img.Image cropped;
      if (mmPerPx != null) {
        final double scalaFattore = mmPerPx / _targetMmPerPx;

        // Lato quadrato nel RAW: partiamo dal lato corto del RAW, poi correggiamo per la scala
        final int shortRaw = math.min(original.width, original.height);
        int sidePx = (shortRaw / scalaFattore).round();
        sidePx = sidePx.clamp(64, shortRaw);

        // Centro con offset verticale -0.3 come in preview
        final int centerX = original.width ~/ 2;
        final int centerY = (original.height ~/ 2) +
            (_offsetFactorY * (original.height ~/ 2)).round();

        final int x = (centerX - sidePx ~/ 2).clamp(0, original.width - sidePx);
        final int y = (centerY - sidePx ~/ 2).clamp(0, original.height - sidePx);

        cropped = img.copyCrop(original, x: x, y: y, width: sidePx, height: sidePx);
      } else {
        // Fallback: quadrato centrale massimo
        final int side =
            original.width < original.height ? original.width : original.height;
        final int x = (original.width - side) ~/ 2;
        final int y = (original.height - side) ~/ 2;
        cropped = img.copyCrop(original, x: x, y: y, width: side, height: side);
      }

      // Ridimensiona a 1024×1024
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);

      // Flip orizzontale se camera frontale (per coerenza con preview)
      if (ctrl.description.lensDirection == CameraLensDirection.front) {
        resized = img.flipHorizontal(resized);
      }

      // Salvataggio su file (puoi sostituire con ImageGallerySaver se vuoi salvarlo in galleria)
      final String outPath = shot.path.replaceFirst(
        RegExp(r'\.(heic|jpeg|jpg|png)$', caseSensitive: false),
        '_1024.jpg',
      );
      await File(outPath).writeAsBytes(img.encodeJpg(resized, quality: 95));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto 1024×1024 salvata in scala')),
        );
      }
    } catch (e) {
      debugPrint('Take/save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      try {
        if (!ctrl.value.isStreamingImages) {
          await ctrl.startImageStream(_processCameraImage);
          _streamRunning = true;
        }
      } catch (_) {}
      if (mounted) setState(() => _shooting = false);
    }
  }

  // ===== UI: badge stato scala =====
  Widget _buildScaleBadge() {
    final m = _mmPerPxAttuale;
    Color c;
    String text;

    if (m == null) {
      c = Colors.grey;
      text = (_mode == CaptureMode.volto)
          ? 'Inquadra gli occhi • calcolo scala…'
          : 'Mostra gli occhi 1s per calibrare (63 mm)';
    } else if (_scaleOk) {
      c = Colors.green;
      text = (_mode == CaptureMode.volto)
          ? 'OK • 0.117 mm/px'
          : 'OK • 12 cm in 1024 px';
    } else {
      c = Colors.amber;
      text = (m > _targetMmPerPx)
          ? 'LONTANO • avvicinati (mm/px=${m.toStringAsFixed(3)})'
          : 'VICINO • allontanati (mm/px=${m.toStringAsFixed(3)})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: _badgeBorder),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  // ===== UI: selettore tab =====
  Widget _buildModeSelector() {
    Widget chip(String text, CaptureMode value) {
      final bool selected = _mode == value;
      return GestureDetector(
        onTap: () => setState(() {
          _mode = value;
          // Non azzeriamo il lock: la calibrazione resta valida tra tab
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white10,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: 1.6,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
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

  // ===== UI: preview + overlay riquadro =====
  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile', style: TextStyle(color: Colors.white)));
    }

    final bool isFront = ctrl.description.lensDirection == CameraLensDirection.front;
    final Size p = ctrl.value.previewSize ?? const Size(1080, 1440);

    Widget inner = SizedBox(
      width: p.height, // previewSize è landscape
      height: p.width,
      child: CameraPreview(ctrl),
    );

    if (isFront) {
      inner = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0), // mirror preview
        child: inner,
      );
    }

    final previewFull = FittedBox(
      fit: BoxFit.cover,
      child: inner,
    );

    Widget overlay = LayoutBuilder(
      builder: (context, constraints) {
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;
        final double shortSide = math.min(screenW, screenH);

        // dimensione riquadro: se ho mm/px → scala come target; altrimenti fallback 70% lato corto
        double squareSize;
        final m = _mmPerPxAttuale;
        if (m != null) {
          final double scalaFattore = m / _targetMmPerPx;
          squareSize = (shortSide / scalaFattore).clamp(32.0, shortSide);
        } else {
          squareSize = shortSide * 0.70;
        }

        final Color frameColor = _scaleOk ? Colors.green : Colors.yellow.withOpacity(0.95);
        final double safeTop = MediaQuery.of(context).padding.top;

        return Stack(
          children: [
            Align(
              alignment: Alignment(0, _offsetFactorY),
              child: Container(
                width: squareSize,
                height: squareSize,
                decoration: BoxDecoration(
                  border: Border.all(color: frameColor, width: _frameThickness),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              top: safeTop + 8,
              left: 0,
              right: 0,
              child: Center(child: _buildScaleBadge()),
            ),
            Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(child: _buildModeSelector()),
            ),
          ],
        );
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: previewFull),
        Positioned.fill(child: overlay),
      ],
    );
  }

  // ===== UI: bottom bar =====
  Widget _buildBottomBar() {
    final canShoot = _controller != null &&
        _controller!.value.isInitialized &&
        !_shooting &&
        _mmPerPxAttuale != null; // scatta solo se c'è calibrazione

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // switch camera
            IconButton(
              iconSize: 28,
              onPressed: (_cameras.length >= 2) ? _switchCamera : null,
              icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
              style: ButtonStyle(
                backgroundColor: const WidgetStatePropertyAll(Colors.black26),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            // pulsante scatto
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _mode == CaptureMode.volto
                          ? 'Inquadra gli occhi finché il riquadro non è verde.'
                          : 'In PARTIOLARE mostra prima gli occhi 1s per calibrare (63 mm).',
                    ),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 6),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: _shooting ? 60 : 66,
                      height: _shooting ? 60 : 66,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // placeholder simmetrico
            const SizedBox(width: 52, height: 52),
          ],
        ),
      ),
    );
  }

  // ===== Lifecycle =====
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (state == AppLifecycleState.inactive) {
      try {
        if (_streamRunning) {
          _controller?.stopImageStream();
          _streamRunning = false;
        }
      } catch (_) {}
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameras[_cameraIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_streamRunning) {
        _controller?.stopImageStream();
      }
    } catch (_) {}
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
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