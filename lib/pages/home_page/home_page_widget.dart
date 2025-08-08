// === IMPORT AUTOMATICI FLUTTERFLOW ===
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:custom_camera_component/index.dart'; // ✅ FIX percorso corretto
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

// === LIBRERIE AGGIUNTIVE ===
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';     // Haptic feedback
import 'package:flutter/foundation.dart';   // compute()
import 'dart:io';
import 'dart:typed_data';

// ====== PARAMETRI RAPIDI ======
const double squareOffsetY = -0.4;     // -1 = su, 0 = centro, 1 = giù
const bool showGrid = true;            // griglia 3x3
const double squareScale = 0.9;        // grandezza riquadro guida
const Color brandColor = Color(0xFF1F4E78);
// =================================

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _shutterBlink = false;          // flash bianco breve
  String? lastPhotoPath;               // path ultima foto per thumbnail

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  // ---------- WORKER in ISOLATE: crop + resize 1024 ----------
  static Uint8List _cropResizeWorker(Uint8List srcBytes) {
    final original = img.decodeImage(srcBytes);
    if (original == null) return srcBytes;

    final size = original.width < original.height ? original.width : original.height;
    final x = (original.width - size) ~/ 2;
    final y = (original.height - size) ~/ 2;
    final cropped = img.copyCrop(original, x: x, y: y, width: size, height: size);

    final resized = img.copyResize(
      cropped,
      width: 1024,
      height: 1024,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 100));
  }

  // Attesa bytes nuovi (evita foto precedente)
  Future<Uint8List?> _waitForShotBytes({int timeoutMs = 3000}) async {
    final prevB64 = FFAppState().fileBase64;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      final b64 = FFAppState().fileBase64;
      if (b64.isNotEmpty && b64 != prevB64) {
        final f = functions.base64toFile(b64);
        if (f != null && f.bytes != null) {
          return Uint8List.fromList(f.bytes!);
        }
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return null;
  }

  Future<String?> _saveBytesToGallery(Uint8List bytes) async {
    final tempPath =
        '${Directory.systemTemp.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(tempPath);
    await f.writeAsBytes(bytes, flush: true);
    await GallerySaver.saveImage(f.path);
    return f.path;
  }

  // Effetto otturatore (blink)
  void _shutterFX() {
    setState(() => _shutterBlink = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _shutterBlink = false);
    });
  }

  // Elaborazione in background
  Future<void> _processAfterShot() async {
    final srcBytes = await _waitForShotBytes();
    if (srcBytes == null) return;

    // Crop/resize in isolate
    final outBytes = await compute<Uint8List, Uint8List>(_cropResizeWorker, srcBytes);

    // Salva e aggiorna thumbnail
    final savedPath = await _saveBytesToGallery(outBytes);
    if (!mounted || savedPath == null) return;
    setState(() {
      lastPhotoPath = savedPath;
    });
  }

  // Tap: scatta subito
  void _shoot() {
    HapticFeedback.lightImpact();
    _shutterFX();

    FFAppState().fileBase64 = '';
    FFAppState().makePhoto = true;
    safeSetState(() {});

    _processAfterShot(); // background
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
          backgroundColor: brandColor,
          automaticallyImplyLeading: false,
          title: Text(
            'Epidermys',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  color: Colors.white,
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                ),
          ),
          centerTitle: false,
          elevation: 2.0,
        ),
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              // Preview fotocamera full screen
              Positioned.fill(
                child: custom_widgets.CameraPhoto(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              // Griglia 3x3
              if (showGrid)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final h = c.maxHeight;
                      return Stack(
                        children: [
                          Positioned(left: w / 3, top: 0, bottom: 0, child: Container(width: 1, color: Colors.white24)),
                          Positioned(left: 2 * w / 3, top: 0, bottom: 0, child: Container(width: 1, color: Colors.white24)),
                          Positioned(top: h / 3, left: 0, right: 0, child: Container(height: 1, color: Colors.white24)),
                          Positioned(top: 2 * h / 3, left: 0, right: 0, child: Container(height: 1, color: Colors.white24)),
                        ],
                      );
                    },
                  ),
                ),

              // Riquadro guida 1:1
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final size = (w < h ? w : h) * squareScale;
                  return IgnorePointer(
                    child: Align(
                      alignment: Alignment(0, squareOffsetY),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Blink bianco otturatore
              AnimatedOpacity(
                opacity: _shutterBlink ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 80),
                child: Container(color: Colors.white),
              ),

              // Thumbnail ultima foto
              if (lastPhotoPath != null)
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(lastPhotoPath!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              // Pulsante scatto rotondo
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: GestureDetector(
                    onTap: _shoot,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: brandColor.withOpacity(0.08),
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                        Container(
                          width: 68,
                          height: 68,
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
          ),
        ),
      ),
    );
  }
}