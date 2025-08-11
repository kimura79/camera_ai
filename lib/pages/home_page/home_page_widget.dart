import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

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
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
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

  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
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
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;

    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameras[_cameraIndex]);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile'));
    }

    // Preview nativa
    final preview = AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: CameraPreview(ctrl),
    );

    // *** Riquadro 1:1 spostato IN ALTO (circa 30% dall'alto) ***
    final overlay = LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final double maxH = constraints.maxHeight;
        final double size = (maxW < maxH) ? maxW : maxH;

        return IgnorePointer(
          child: Stack(
            children: [
              // quadrato guida posizionato in alto
              Positioned(
                top: maxH * 0.18, // sposta più/meno in alto (regola se vuoi)
                left: (maxW - size) / 2,
                width: size,
                child: Center(
                  child: SizedBox(
                    width: size * 0.70, // leggermente più piccolo del pieno
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

  // === Pulsante scatto stile iPhone + thumbnail + switch ===
  Widget _buildBottomBar() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_shooting;

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

            // **Pulsante scatto stile iPhone**
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // anello esterno
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    // bordo bianco spesso (anello)
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 6),
                      ),
                    ),
                    // disco interno bianco
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: _shooting ? 58 : 64, // leggero feedback
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

            // Switch camera destra
            IconButton(
              iconSize: 30,
              onPressed: (_cameras.length >= 2) ? _switchCamera : null,
              icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
              style: ButtonStyle(
                backgroundColor:
                    const WidgetStatePropertyAll(Colors.black26),
                padding:
                    const WidgetStatePropertyAll(EdgeInsets.all(10)),
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