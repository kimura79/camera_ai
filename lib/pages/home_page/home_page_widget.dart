// 🔹 home_page_widget.dart — Flusso: Calibra occhi → Close-up
// Scala 0,117 mm/px (12 cm in 1024 px), bordo spesso + glow, riquadro alzato del 30%
// IPD virtuale 63 mm; calibrazione auto con lock quando stabile; crop allineato all’overlay

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
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

  // ====== Modalità ======
  CaptureMode _mode = CaptureMode.volto;

  // ====== Parametri scala / UI ======
  static const double _targetMmPerPx = 0.117; // 12 cm / 1024 px
  static const double _offsetFactorY = -0.3;  // riquadro alzato del 30%
  static const double _tolerance = 0.05;      // ±5%
  static const double kFrameThickness = 8.0;  // bordo spesso riquadro
  static const double kBadgeBorder = 3.0;     // bordo badge
  static const double kGlowOpacity = 0.28;    // intensità glow bordo

  // IPD virtuale
  static const double _ipdMm = 63.0;
  double _lastIpdPx = 0.0; // IPD attuale da preview

  // Calibrazione (lock) riutilizzabile tra modalità
  bool _locked = false;
  double? _lockedMmPerPx; // mm/px bloccato
  DateTime? _lockCandidateStart; // per stabilità 0.6s

  // Helper scala attuale (preferisce lock se esiste)
  bool get _hasCalibration => _lockedMmPerPx != null;
  double? get _mmPerPxAttuale =>
      _hasCalibration ? _lockedMmPerPx : (_lastIpdPx > 0 ? _ipdMm / _lastIpdPx : null);

  bool get _scaleOkCurrent {
    final m = _mmPerPxAttuale;
    if (m == null) return false;
    final err = (m - _targetMmPerPx).abs() / _targetMmPerPx;
    return err <= _tolerance;
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
      await ctrl.setZoomLevel(1.0); // 🔒 zoom fisso 1×
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

  // ====== ML Kit sempre attivo: in Volto si calibra, in Particolare mantiene lock ======
  Future<void> _processCameraImage(CameraImage image) async {
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
        _onNoFace();
        return;
      }
      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        _onNoFace();
        return;
      }
      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      _updateCalibration(distPx);
    } catch (_) {
      // ignora in preview
    }
  }

  void _onNoFace() {
    if (!_locked) {
      // Se non ho lock, resetto candidate
      _lockCandidateStart = null;
      setState(() => _lastIpdPx = 0.0);
    }
  }

  void _updateCalibration(double ipdPx) {
    // Aggiorno valore istantaneo
    if (!_locked) {
      setState(() => _lastIpdPx = ipdPx);
      // Se sono in modalità VOLTO e la scala è in range, avvio finestra di stabilità
      final mmPerPx = _ipdMm / ipdPx;
      final inRange = (mmPerPx - _targetMmPerPx).abs() / _targetMmPerPx <= _tolerance;

      if (_mode == CaptureMode.volto && inRange) {
        final now = DateTime.now();
        _lockCandidateStart ??= now;
        // Se rimane stabile per 0.6s, faccio lock automatico e passo a "particolare"
        if (now.difference(_lockCandidateStart!).inMilliseconds >= 600) {
          setState(() {
            _locked = true;
            _lockedMmPerPx = mmPerPx;
            _lockCandidateStart = null;
            _mode = CaptureMode.particolare; // auto switch al close-up
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Calibrazione bloccata • Passo a close-up')),
          );
        }
      } else {
        // non in range → resetto finestra di stabilità
        _lockCandidateStart = null;
      }
    } else {
      // Se già lockato, ignoro aggiornamenti (resto stabile)
    }
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

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      final img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      // ===== Crop coerente con riquadro (VOLTO/PARTICOLARE) =====
      img.Image cropped;
      final double? mmPerPx = _mmPerPxAttuale;

      if (mmPerPx != null) {
        // scalaFattore = (mm/px attuale) / (mm/px target)
        final double scalaFattore = mmPerPx / _targetMmPerPx;

        // Lato crop nel RAW = lato corto RAW / scalaFattore
        final int shortRaw = math.min(original.width, original.height);
        int sidePx = (shortRaw / scalaFattore).round();
        sidePx = sidePx.clamp(64, shortRaw);

        // Centro con offset verticale come overlay (Alignment(0, -0.3))
        final int centerX = original.width ~/ 2;
        final int centerY = (original.height ~/ 2) +
            (_offsetFactorY * (original.height ~/ 2)).round();

        final int x = (centerX - sidePx ~/ 2).clamp(0, original.width - sidePx);
        final int y = (centerY - sidePx ~/ 2).clamp(0, original.height - sidePx);

        cropped = img.copyCrop(
          original,
          x: x,
          y: y,
          width: sidePx,
          height: sidePx,
        );
      } else {
        // fallback: crop centrale max 1:1
        final int side =
            original.width < original.height ? original.width : original.height;
        final int x = (original.width - side) ~/ 2;
        final int y = (original.height - side) ~/ 2;
        cropped = img.copyCrop(original, x: x, y: y, width: side, height: side);
      }

      // Ridimensiona a 1024×1024
      img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);

      // Selfie specchiato sul frontale
      if (isFront) {
        resized = img.flipHorizontal(resized);
      }

      final Uint8List croppedBytes =
          Uint8List.fromList(img.encodeJpg(resized, quality: 95));

      await ImageGallerySaver.saveImage(
        croppedBytes,
        name:
            '${_mode == CaptureMode.particolare ? 'particolare' : 'volto'}_1024_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

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

    final m = _mmPerPxAttuale;
    final inRange = _scaleOkCurrent;

    if (!_locked) {
      if (m == null || _lastIpdPx == 0) {
        c = Colors.grey;
        text = 'Inquadra gli occhi • calcolo scala…';
      } else if (!inRange) {
        c = Colors.amber;
        final dir = (m > _targetMmPerPx) ? 'LONTANO • avvicinati' : 'VICINO • allontanati';
        text = '$dir  (mm/px=${m.toStringAsFixed(3)})';
      } else {
        c = Colors.green;
        text = 'OK • 0.117 mm/px (stabile… blocco auto)';
      }
    } else {
      if (inRange) {
        c = Colors.green;
        text = 'Calibrato • 12 cm in 1024 px';
      } else {
        // in close-up può variare un po’, mostriamo direzione
        c = Colors.amber;
        final dir = (m! > _targetMmPerPx) ? 'LONTANO • avvicinati' : 'VICINO • allontanati';
        text = '$dir  (mm/px=${m.toStringAsFixed(3)})';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: kBadgeBorder),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(kGlowOpacity),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _buildModeSelector() {
    Widget chip(String text, CaptureMode value) {
      final bool selected = _mode == value;
      return GestureDetector(
        onTap: () async {
          setState(() => _mode = value);
          if (_controller != null && _controller!.value.isInitialized) {
            await _controller!.setZoomLevel(1.0);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: 1.6,
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
        chip('volto', CaptureMode.volto),
        const SizedBox(width: 10),
        chip('particolare', CaptureMode.particolare),
      ],
    );
  }

  Widget _buildTopButtons() {
    final canLockManually = !_locked && _lastIpdPx > 0 && _scaleOkCurrent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canLockManually)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _locked = true;
                  _lockedMmPerPx = _ipdMm / _lastIpdPx;
                  _lockCandidateStart = null;
                  _mode = CaptureMode.particolare;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔒 Calibrazione bloccata')),
                );
              },
              icon: const Icon(Icons.lock),
              label: const Text('Usa subito'),
            ),
          ),
        if (_locked)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _locked = false;
                  _lockedMmPerPx = null;
                  _lockCandidateStart = null;
                  _mode = CaptureMode.volto;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔁 Ricalibra sugli occhi')),
                );
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Ricalibra'),
            ),
          ),
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
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;
        final double shortSide = math.min(screenW, screenH);

        // calcolo riquadro in scala (se calibrato o con IPD attivo)
        double squareSize;
        final m = _mmPerPxAttuale;
        if (m != null) {
          final double scalaFattore = m / _targetMmPerPx;
          squareSize = (shortSide / scalaFattore).clamp(32.0, shortSide);
        } else {
          squareSize = shortSide * 0.70; // prima della calibrazione
        }

        final bool okScale = _scaleOkCurrent;
        final Color frameColor =
            okScale ? Colors.green : Colors.yellow.withOpacity(0.95);
        final double safeTop = MediaQuery.of(context).padding.top;

        return Stack(
          children: [
            // riquadro 1:1 ALZATO del 30% — BORDO SPESSO + glow
            Align(
              alignment: Alignment(0, _offsetFactorY),
              child: Container(
                width: squareSize,
                height: squareSize,
                decoration: BoxDecoration(
                  border: Border.all(color: frameColor, width: kFrameThickness),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: frameColor.withOpacity(kGlowOpacity),
                      blurRadius: 16,
                      spreadRadius: 1.5,
                    ),
                  ],
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
            // tasti lock/ri-calibra
            Positioned(
              top: safeTop + 52,
              left: 0,
              right: 0,
              child: _buildTopButtons(),
            ),
            // selector volto/particolare
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
        Positioned.fill(child: previewFull),
        Positioned.fill(child: overlay),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // thumbnail ultimo scatto
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

            // pulsante scatto
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

            // switch camera
            IconButton(
              iconSize: 30,
              onPressed: (_cameras.length >= 2) ? _switchCamera : null,
              icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
              style: ButtonStyle(
                backgroundColor:
                    const WidgetStatePropertyAll(Colors.black26),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          elevation: 0,
          title: Text(
            'Epidermys camera',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  color: Colors.white,
                  fontSize: 20,
                ),
          ),
        ),
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
      ),
    );
  }
}