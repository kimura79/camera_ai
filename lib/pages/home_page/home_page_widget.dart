// 🔹 home_page_widget.dart — Fullscreen cover + volto in scala 0,117; crop 1024x1024; riquadro alzato del 30%
//     Bordo quadrato più spesso per visibilità colore
//
// Calibrazione IPD attiva anche su "PARTICOLARE" + crop identico al riquadro overlay

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

// ML Kit usato in modalità "volto"
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

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
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;

  String? _lastShotPath;

  // Modalità selezionata
  CaptureMode _mode = CaptureMode.volto;

  // ====== Parametri scala ======
  final double _targetMmPerPx = 0.117; // mm/px

  // Volto (ML Kit, IPD)
  double _ipdMm = 63.0;
  double get _targetPxVolto => _ipdMm / _targetMmPerPx; // ~539 px
  double _lastIpdPx = 0.0; // IPD misurata in px nella preview
  bool _scaleOkVolto = false;

  // Particolare (12 cm)
  static const double _targetMmPart = 120.0; // 12 cm
  double get _targetPxPart => _targetMmPart / _targetMmPerPx; // ~1026 px

  // Usa calibrazione IPD anche per particolare
  bool get _scaleOkPart {
    if (_lastIpdPx <= 0) return false;
    final mmPerPxAttuale = _ipdMm / _lastIpdPx;
    final err = (mmPerPxAttuale - _targetMmPerPx).abs() / _targetMmPerPx;
    return err <= 0.05; // ±5%
  }

  // ====== ML Kit ======
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);
  bool _streamRunning = false;

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
      await ctrl.setZoomLevel(1.0); // 🔒 Zoom fisso 1×
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

  // ====== Stream → ML Kit ATTIVO in entrambe le modalità (volto + particolare) ======
  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 300) return;
    _lastProc = now;

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      final rotation = _rotationFromSensor(ctrl.description.sensorOrientation);
      final inputImage = _inputImageFromCameraImage(image, rotation);

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        _updateScaleVolto(null);
        return;
      }
      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        _updateScaleVolto(null);
        return;
      }
      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      _updateScaleVolto(distPx);
    } catch (_) {}
  }

  void _updateScaleVolto(double? ipdPx) {
    final double tgt = _targetPxVolto;
    final double minT = tgt * 0.95;
    final double maxT = tgt * 1.05;

    bool ok = false;
    double shown = 0;
    if (ipdPx != null && ipdPx.isFinite) {
      shown = ipdPx;
      ok = (ipdPx >= minT && ipdPx <= maxT);
    }
    if (!mounted) return;
    setState(() {
      _lastIpdPx = shown;
      _scaleOkVolto = ok;
    });
  }

  // ====== Helpers ML Kit ======
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

  // ====== Scatto + salvataggio ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      if (_streamRunning) {
        await ctrl.stopImageStream();
        _streamRunning = false;
      }

      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      // 1) Scatto + decodifica
      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      // 2) Per la front: flip SUBITO per allineare alle coordinate della preview specchiata
      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // 3) Geometria della preview (FittedBox.cover) + overlay (stessa logica dell'UI)
      final Size p = ctrl.value.previewSize ?? const Size(1080, 1440);
      final double previewW = p.height.toDouble(); // previewSize è landscape
      final double previewH = p.width.toDouble();

      final Size screen = MediaQuery.of(context).size;
      final double screenW = screen.width;
      final double screenH = screen.height;

      // scala di BoxFit.cover
      final double scale = math.max(screenW / previewW, screenH / previewH);
      final double dispW = previewW * scale;
      final double dispH = previewH * scale;
      final double dx = (screenW - dispW) / 2.0; // offset sinistro del contenuto
      final double dy = (screenH - dispH) / 2.0; // offset superiore del contenuto

      // lato corto visibile
      final double shortSideScreen = math.min(screenW, screenH);

      // dimensione del riquadro come overlay
      double squareSizeScreen;
      if (_lastIpdPx > 0) {
        final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
        final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;
        squareSizeScreen =
            (shortSideScreen / scalaFattore).clamp(32.0, shortSideScreen);
      } else {
        squareSizeScreen = shortSideScreen * 0.70; // fallback
      }

      // centro riquadro con offset -0.3 (stessa Align dell'overlay)
      final double centerXScreen = screenW / 2.0;
      final double centerYScreen = (screenH / 2.0) + (-0.3) * (screenH / 2.0);

      final double leftScreen = centerXScreen - squareSizeScreen / 2.0;
      final double topScreen  = centerYScreen - squareSizeScreen / 2.0;

      // 4) Trasforma SCHERMO → preview visibile → spazio preview → RAW
      final double leftInShown = leftScreen - dx;
      final double topInShown  = topScreen  - dy;

      final double leftPreview = leftInShown / scale;
      final double topPreview  = topInShown  / scale;
      final double sidePreview = squareSizeScreen / scale;

      final double ratioX = original.width  / previewW;
      final double ratioY = original.height / previewH;

      int cropX    = (leftPreview * ratioX).round();
      int cropY    = (topPreview  * ratioY).round();
      int cropSide = (sidePreview * math.min(ratioX, ratioY)).round();

      // 5) Clamping ai bordi
      cropSide = cropSide.clamp(1, math.min(original.width, original.height));
      cropX    = cropX.clamp(0, original.width  - cropSide);
      cropY    = cropY.clamp(0, original.height - cropSide);

      // 6) Crop RAW esattamente corrispondente al riquadro overlay
      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSide,
        height: cropSide,
      );

      // 7) Resize a 1024×1024 (nessun flip qui: già fatto PRIMA se front)
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);

      final Uint8List croppedBytes =
          Uint8List.fromList(img.encodeJpg(resized, quality: 95));

      // 8) Salvataggio
      await ImageGallerySaver.saveImage(
        croppedBytes,
        name:
            '${_mode == CaptureMode.particolare ? 'particolare' : 'volto'}_1024_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Aggiorna thumbnail
      final String newPath = shot.path.replaceFirst(
        RegExp(r'\.(heic|jpeg|jpg|png)$', caseSensitive: false),
        '_1024.jpg',
      );
      await File(newPath).writeAsBytes(croppedBytes);
      _lastShotPath = newPath;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto 1024×1024 salvata')),
        );
        setState(() {});
      }
    } catch (e) {
      debugPrint('Take/save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio: $e')),
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

  // ====== UI ======
  Widget _buildScaleChip() {
    Color c;
    String text;
    if (_mode == CaptureMode.volto) {
      final double tgt = _targetPxVolto;
      final double minT = tgt * 0.95;
      final double maxT = tgt * 1.05;
      final v = _lastIpdPx;
      if (v == 0) {
        c = Colors.grey;
      } else if (v < minT * 0.9 || v > maxT * 1.1) {
        c = Colors.red;
      } else if (v < minT || v > maxT) {
        c = Colors.amber;
      } else {
        c = Colors.green;
      }
      text = 'Centra il viso – scatta solo col verde';
    } else {
      c = _scaleOkPart ? Colors.green : Colors.amber;
      text = 'Particolare 12 cm – scatta solo col verde';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1.6),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _buildModeSelector() {
    Widget chip(String text, CaptureMode value) {
      final bool selected = _mode == value;
      return GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

    // Dimensioni natie della preview (in landscape)
    final Size p = ctrl.value.previewSize ?? const Size(1080, 1440);

    // ---- PREVIEW FULLSCREEN tipo Fotocamera (cover) ----
    Widget inner = SizedBox(
      width: p.height, // invertiti perché la previewSize è landscape
      height: p.width,
      child: CameraPreview(ctrl),
    );

    if (isFront) {
      inner = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: inner,
      );
    }

    final previewFull = FittedBox(
      fit: BoxFit.cover, // riempi tutto lo schermo
      child: inner,
    );

    // ---- OVERLAY sulla stessa area visibile (cover) ----
    Widget overlay = LayoutBuilder(
      builder: (context, constraints) {
        // il riquadro lo disegniamo rispetto all'area VISIBILE (tutto schermo)
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;
        final double shortSide = math.min(screenW, screenH);

        // calcolo riquadro in scala, in entrambe le tab
        double squareSize;
        if (_lastIpdPx > 0) {
          final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
          final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;
          squareSize = (shortSide / scalaFattore).clamp(32.0, shortSide);
        } else {
          squareSize = shortSide * 0.70; // fallback prima della calibrazione
        }

        final Color frameColor = (_mode == CaptureMode.volto
                ? _scaleOkVolto
                : _scaleOkPart)
            ? Colors.green
            : Colors.yellow.withOpacity(0.95);

        final double safeTop = MediaQuery.of(context).padding.top;

        return Stack(
          children: [
            // riquadro 1:1 ALZATO del 30% — BORDO SPESSO
            Align(
              alignment: const Alignment(0, -0.3),
              child: Container(
                width: squareSize,
                height: squareSize,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: frameColor,
                    width: 4, // bordo più spesso
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            // badge
            Positioned(
              top: safeTop + 8,
              left: 0,
              right: 0,
              child: Center(child: _buildScaleChip()),
            ),
            // selector
            Positioned(
              bottom: 180,
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
        Positioned.fill(child: previewFull), // FULL SCREEN
        Positioned.fill(child: overlay),     // overlay allineato
      ],
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
            // ✅ THUMBNAIL A SINISTRA
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

            // PULSANTE SCATTO AL CENTRO
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

            // ✅ REVERSE CAMERA A DESTRA
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

  // ====== Lifecycle ======
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
    _model.dispose();
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