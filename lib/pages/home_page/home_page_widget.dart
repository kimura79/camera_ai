// === IMPORT FLUTTERFLOW (lasciamo solo quelli che servono a stile/titolo) ===
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// CAMERA ufficiale
import 'package:camera/camera.dart';

// Per la mini anteprima: salviamo in temp e mostriamo con Image.file
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

import 'home_page_model.dart';
export 'home_page_model.dart';

// ================== PARAMETRI MINIMI ==================
const Color brandColor = Color(0xFF1F4E78);
const double squareScale = 0.86;   // grandezza bordo guida rispetto al lato min
const double squareOffsetY = 0.0; // 0 = centro, valori negativi = più in alto
// ======================================================

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});
  static String routeName = 'HomePage';
  static String routePath  = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with WidgetsBindingObserver {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Camera
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _initError = false;

  // Thumbnail ultimo scatto
  String? _lastPhotoPath;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _model.dispose();
    super.dispose();
  }

  // Lifecycle: evita schermate nere al rientro
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.inactive) {
      await controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await _reinitCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      final CameraDescription cam = _cameras.isEmpty
          ? throw 'Nessuna camera trovata'
          : // preferisci frontale per selfie
          (_cameras.any((c) => c.lensDirection == CameraLensDirection.front)
              ? _cameras.firstWhere((c) =>
                  c.lensDirection == CameraLensDirection.front)
              : _cameras.first);

      _controller = CameraController(
        cam,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _initError = false);
    } catch (e) {
      _initError = true;
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _reinitCamera() async {
    await _disposeCamera();
    await _initCamera();
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty || _controller == null) return;
    final current = _controller!.description;
    CameraDescription next;

    if (_cameras.length == 1) return; // niente da switchare

    if (current.lensDirection == CameraLensDirection.front) {
      next = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => current,
      );
    } else {
      next = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => current,
      );
    }

    await _controller?.dispose();
    _controller = CameraController(
      next,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _shoot() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final xfile = await _controller!.takePicture();
      // salviamo in temp e mostriamo thumbnail
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/last_shot.jpg';
      await File(xfile.path).copy(outPath);
      if (!mounted) return;
      setState(() => _lastPhotoPath = outPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Errore scatto: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: brandColor,
        title: Text(
          'Epidermys (STEP MINIMO)',
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
        elevation: 2,
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_initError) {
      return _centerText(
        'Impossibile inizializzare la fotocamera.\n'
        'Controlla i permessi in Impostazioni > ${Platform.isIOS ? "Privacy > Fotocamera" : "App > Permessi"}',
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;

        // === Quadrato 1:1 (solo bordo, nessuna maschera) ===
        final side = (w < h ? w : h) * squareScale;
        final left = (w - side) / 2;
        final top  = (h - side) / 2 + (h * squareOffsetY / 2);

        // Selfie: anteprima specchiata per coerenza con camera nativa
        final preview = _controller!.description.lensDirection == CameraLensDirection.front
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                child: CameraPreview(_controller!),
              )
            : CameraPreview(_controller!);

        return Stack(
          children: [
            // 1) PREVIEW FULL SCREEN
            Positioned.fill(child: preview),

            // === DIAGNOSTICA in alto ===
            Positioned(
              left: 8, top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  [
                    'cams: ${_cameras.length}',
                    'inited: ${_controller?.value.isInitialized == true}',
                    'hasErr: ${_controller?.value.hasError == true}',
                    'err: ${_controller?.value.errorDescription ?? '-'}',
                    'lens: ${_controller?.description.lensDirection.name ?? '-'}',
                  ].join(' | '),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),

            // 2) QUADRATO 1:1 SOLO BORDO (nessun riempimento!)
            Positioned(
              left: left,
              top: top,
              width: side,
              height: side,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            // 3) THUMBNAIL in basso a sinistra
            if (_lastPhotoPath != null)
              Positioned(
                left: 16,
                bottom: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_lastPhotoPath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // 4) SWITCH CAMERA in basso a destra
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton(
                heroTag: 'switchCam',
                mini: true,
                backgroundColor: Colors.black54,
                onPressed: _switchCamera,
                child: const Icon(Icons.cameraswitch, color: Colors.white),
              ),
            ),

            // 5) PULSANTE SCATTO al centro in basso
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: GestureDetector(
                  onTap: _shoot,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                      ),
                      Container(
                        width: 66,
                        height: 66,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _centerText(String s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
}