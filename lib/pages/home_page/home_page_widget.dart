// 🔹 home_page_widget.dart — Fullscreen cover + volto in scala 0,117; crop 1024x1024; riquadro alzato del 30%

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
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

// ✅ NUOVA PAGINA: risultati analisi con overlay macchie + rughe
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
  final File? guideImage; // 👈 aggiunto

  const HomePageWidget({
    super.key,
    this.guideImage, // 👈 aggiunto
  });

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

  final double _targetMmPerPx = 0.117;

  double _ipdMm = 63.0;
  double get _targetPxVolto => _ipdMm / _targetMmPerPx;
  double _lastIpdPx = 0.0;
  bool _scaleOkVolto = false;

  static const double _targetMmPart = 120.0;
  double get _targetPxPart => _targetMmPart / _targetMmPerPx;

  bool get _scaleOkPart {
    if (_lastIpdPx <= 0) return false;

    // Calcolo distanza stimata in cm per PARTICOLARE
    final mmPerPxAttuale = _ipdMm / _lastIpdPx;
    final larghezzaRealeMm = mmPerPxAttuale * 1024.0;
    final distanzaCm = (larghezzaRealeMm / 10.0) * 2.0; // stesso calcolo badge

    // Verde solo se 11–13 cm
    return (distanzaCm >= 11.0 && distanzaCm <= 13.0);
  }

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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      await ctrl.setZoomLevel(1.0);
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

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 800) return; // meno fps → meno lag
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

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

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
      final double shortSideScreen = math.min(screenW, screenH);

      double squareSizeScreen;
      if (_lastIpdPx > 0) {
        final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
        final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;
        squareSizeScreen =
            (shortSideScreen / scalaFattore).clamp(32.0, shortSideScreen);
      } else {
        squareSizeScreen = shortSideScreen * 0.70;
      }

      final double centerXScreen = screenW / 2.0;
      final double centerYScreen =
          screenH / 2.0 + (-0.4 * squareSizeScreen / 2.0);

      final double leftScreen = centerXScreen - squareSizeScreen / 2.0;
      final double topScreen = centerYScreen - squareSizeScreen / 2.0;

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

      img.Image cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSide,
        height: cropSide,
      );

      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));

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
          '${_mode == CaptureMode.particolare ? 'particolare' : 'volto'}_1024_${DateTime.now().millisecondsSinceEpoch}';

      final AssetEntity? asset = await PhotoManager.editor.saveImage(
        pngBytes,
        filename: '$baseName.png',
      );
      if (asset == null) throw Exception('Salvataggio PNG fallito');

      final String newPath = (await _tempThumbPath('$baseName.png'));
      await File(newPath).writeAsBytes(pngBytes);
      _lastShotPath = newPath;

      debugPrint('✅ PNG salvato — bytes: ${pngBytes.length}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Foto 1024×1024 salvata (PNG lossless)')),
        );
        setState(() {});

        Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => AnalysisPreview(
      imagePath: newPath,
      mode: _mode == CaptureMode.particolare ? "particolare" : "fullface",
    ),
  ),
);
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

  Future<String> _tempThumbPath(String fileName) async {
    final dir = await Directory.systemTemp.createTemp('epi_thumbs');
    return '${dir.path}/$fileName';
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
      text = 'Avvicinati e scatta solo col verde';
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

      return LayoutBuilder(
  builder: (context, constraints) {
    final double screenW = constraints.maxWidth;
    final double screenH = constraints.maxHeight;
    final double shortSide = math.min(screenW, screenH);

    double squareSize;
    if (_lastIpdPx > 0) {
      final double mmPerPxAttuale = _ipdMm / _lastIpdPx;
      final double scalaFattore = mmPerPxAttuale / _targetMmPerPx;
      squareSize = (shortSide / scalaFattore).clamp(300.0, shortSide);
    } else {
      squareSize = shortSide * 0.70;
    }

    final Color frameColor = (_mode == CaptureMode.volto
            ? _scaleOkVolto
            : _scaleOkPart)
        ? Colors.green
        : Colors.yellow.withOpacity(0.95);

    final double safeTop = MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: preview),

        // 👇 Riquadro + overlay guida PRE nello stesso Stack
        Align(
          alignment: const Alignment(0, -0.3),
          child: SizedBox(
            width: squareSize,
            height: squareSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 👇 Immagine PRE in trasparenza (mostrata in volto + particolare)
                if (widget.guideImage != null)
                  Opacity(
                    opacity: 0.4,
                    child: Image.file(
                      widget.guideImage!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),

                // 👇 Cornice verde/gialla
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: frameColor, width: 4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 👇 Overlay distanza cm
        buildDistanzaCmOverlay(
          ipdPx: _lastIpdPx,
          ipdMm: _ipdMm,
          targetMmPerPx: _targetMmPerPx,
          alignY: -0.05,
          mode: _mode,
          isFrontCamera: isFront,
        ),

        // 👇 Livella orizzontale solo in volto
        if (_mode == CaptureMode.volto)
          Align(
            alignment: const Alignment(0, -0.3),
            child: _buildLivellaOrizzontale3Linee(
              width: math.max(squareSize * 0.82, 300.0),
              height: 62,
              okThresholdDeg: 1.0,
            ),
          ),

        // 👇 Chip scala
        Positioned(
          top: safeTop + 8,
          left: 0,
          right: 0,
          child: Center(child: _buildScaleChip()),
        ),

        // 👇 Selettore modalità
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
            buildLivellaVerticaleOverlay(
              mode: _mode,
              topOffsetPx: 65.0,
            ),
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
  Alignment alignment = Alignment.centerRight,
  double size = 120,
  double bubbleSize = 16,
  double fullScaleDeg = 10.0,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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

Widget _buildLivellaOrizzontale3Linee({
  required double width,
  required double height,
  double okThresholdDeg = 1.0,
}) {
  Widget _segment(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h),
        ),
      );

  return StreamBuilder<AccelerometerEvent>(
    stream: accelerometerEventStream(),
    builder: (context, snap) {
      double rollDeg = 0.0;
      if (snap.hasData) {
        final ax = snap.data!.x;
        final ay = snap.data!.y;
        rollDeg = math.atan2(ax, ay) * 180.0 / math.pi;
      }

      final bool isOk = rollDeg.abs() <= okThresholdDeg;
      final Color lineColor = isOk ? Colors.greenAccent : Colors.white;
      final Color bg = Colors.black54;

      final double topRot = (-rollDeg.abs()) * math.pi / 180 / 1.2;
      final double botRot = (rollDeg.abs()) * math.pi / 180 / 1.2;
      final double midRot = (rollDeg) * math.pi / 180;

      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isOk ? Colors.greenAccent : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Transform.rotate(
              angle: topRot,
              child: _segment(width - 40, 2, lineColor),
            ),
            Transform.rotate(
              angle: midRot,
              child: _segment(width - 20, 3, lineColor),
            ),
            Transform.rotate(
              angle: botRot,
              child: _segment(width - 40, 2, lineColor),
            ),
          ],
        ),
      );
    },
  );
}
