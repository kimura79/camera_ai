import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui; // ✅ per WriteBuffer

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

// ML Kit (landmark occhi)
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

  // ====== Calibrazione landmark occhi ======
  final double _targetMmPerPx = 0.117; // obiettivo scala
  double _ipdMm = 63.0; // IPD di riferimento (puoi renderlo configurabile)
  double get _targetPx => _ipdMm / _targetMmPerPx; // ~539 px
  double _lastIpdPx = 0.0;
  bool _scaleOk = false;

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
          (c) => c.lensDirection == CameraLensDirection.back);
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
      imageFormatGroup: ImageFormatGroup.yuv420, // per MLKit
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      // avvia stream per landmark (throttled)
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

  // ====== Image stream -> MLKit (ogni ~300ms) ======
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
        _updateScale(null);
        return;
      }

      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) {
        _updateScale(null);
        return;
      }

      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      _updateScale(distPx);
    } catch (e) {
      // in caso di frame non valido / conversione fallita
      // silenzioso per non disturbare lo scatto
    }
  }

  void _updateScale(double? ipdPx) {
    final double tgt = _targetPx;
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
      _scaleOk = ok;
    });
  }

  // ====== helpers: conversione CameraImage -> InputImage ======
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
    // Concatena i piani YUV420
    final ui.WriteBuffer allBytes = ui.WriteBuffer(); // ✅ fix
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final Uint8List bytes = allBytes.done().buffer.asUint8List();

    final Size size = Size(image.width.toDouble(), image.height.toDouble());
    final planeData = image.planes
        .map(
          (Plane plane) => InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          ),
        )
        .toList();

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: InputImageFormat.yuv420,
      planeData: planeData,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      // stop stream prima dello scatto
      if (_streamRunning) {
        await ctrl.stopImageStream();
        _streamRunning = false;
      }

      final XFile shot = await ctrl.takePicture();
      _lastShotPath = shot.path;

      final Uint8List origBytes = await File(shot.path).readAsBytes();

      // --- Ritaglio 1:1 1024×1024 ---
      final img.Image? original = img.decodeImage(origBytes);
      if (original != null) {
        final int side =
            original.width < original.height ? original.width : original.height;
        final int x = (original.width - side) ~/ 2;
        final int y = (original.height - side) ~/ 2;

        final img.Image square =
            img.copyCrop(original, x: x, y: y, width: side, height: side);
        final img.Image resized =
            img.copyResize(square, width: 1024, height: 1024);

        final Uint8List croppedBytes =
            Uint8List.fromList(img.encodeJpg(resized, quality: 95));

        await ImageGallerySaver.saveImage(
          croppedBytes,
          name: 'photo_cropped_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }

      // Salva anche l'originale
      await ImageGallerySaver.saveImage(
        origBytes,
        name: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Foto salvata (originale + ritaglio 1024x1024)')),
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
      // riavvia stream dopo lo scatto
      try {
        if (!ctrl.value.isStreamingImages) {
          await ctrl.startImageStream(_processCameraImage);
          _streamRunning = true;
        }
      } catch (_) {}
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;

    if (state == AppLifecycleState.inactive) {
      try {
        if (_streamRunning) {
          ctrl.stopImageStream();
          _streamRunning = false;
        }
      } catch (_) {}
      ctrl.dispose();
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

  // ====== UI ======
  Widget _buildScaleChip() {
    // badge stato scala (rosso/giallo/verde)
    final tgt = _targetPx;
    final minT = tgt * 0.95;
    final maxT = tgt * 1.05;

    Color c;
    if (_lastIpdPx == 0) {
      c = Colors.grey;
    } else if (_lastIpdPx < minT * 0.9 || _lastIpdPx > maxT * 1.1) {
      c = Colors.red;
    } else if (_lastIpdPx < minT || _lastIpdPx > maxT) {
      c = Colors.amber;
    } else {
      c = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Text(
        _lastIpdPx == 0
            ? 'Scala: —  (target ~${tgt.toStringAsFixed(0)} px)'
            : 'Scala: ${_lastIpdPx.toStringAsFixed(0)} px  (target ~${tgt.toStringAsFixed(0)})',
        style: const TextStyle(color: Colors.white),
      ),
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

    // Preview nativa (no deformazioni)
    final preview = AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: CameraPreview(ctrl),
    );

    // Riquadro guida 1:1 spostato in alto
    final overlay = LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final double maxH = constraints.maxHeight;
        final double size = (maxW < maxH) ? maxW : maxH;

        return IgnorePointer(
          child: Stack(
            children: [
              // badge scala
              Positioned(
                top: 12,
                left: 12,
                child: _buildScaleChip(),
              ),
              // quadrato guida
              Positioned(
                top: maxH * 0.18,
                left: (maxW - size) / 2,
                width: size,
                child: Center(
                  child: SizedBox(
                    width: size * 0.70,
                    height: size * 0.70,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.yellow.withOpacity(0.95),
                            width: 2,
                          ),
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: preview),
        overlay,
      ],
    );
  }

  Widget _buildBottomBar() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_shooting && _scaleOk;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Thumbnail sinistra
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

            // Pulsante scatto (stile iPhone)
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
                        border: Border.all(
                          color: _scaleOk ? Colors.white : Colors.white24,
                          width: 6,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: _shooting ? 58 : 64,
                      height: _shooting ? 58 : 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _scaleOk ? Colors.white : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Switch camera
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
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            'Custom Camera',
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