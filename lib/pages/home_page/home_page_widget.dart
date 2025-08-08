// === IMPORT FLUTTERFLOW ===
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:custom_camera_component/index.dart'; // <-- usa il nome nel pubspec
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

// === EXTRA ===
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // compute
import 'dart:io';
import 'dart:typed_data';

// ====== PARAMETRI RAPIDI ======
const double squareOffsetY = -0.25;  // -1 su, 0 centro, 1 giù
const double squareScale   = 0.9;    // grandezza riquadro guida
const Color  brandColor    = Color(0xFF1F4E78);
// =================================

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});
  static String routeName = 'HomePage';
  static String routePath  = '/homePage';
  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _shutterBlink = false;
  String? _lastPhotoPath; // solo locale alla pagina

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

  // ---- worker isolate: crop 1:1 centrale + resize 1024 ----
  static Uint8List _cropResizeWorker(Uint8List srcBytes) {
    final original = img.decodeImage(srcBytes);
    if (original == null) return srcBytes;
    final side = original.width < original.height ? original.width : original.height;
    final x = (original.width - side) ~/ 2;
    final y = (original.height - side) ~/ 2;
    final cropped = img.copyCrop(original, x: x, y: y, width: side, height: side);
    final resized = img.copyResize(cropped, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 100));
  }

  // attende bytes NUOVI dal widget camera
  Future<Uint8List?> _waitForShotBytes({int timeoutMs = 4000}) async {
    final prev = FFAppState().fileBase64;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      final b64 = FFAppState().fileBase64;
      if (b64.isNotEmpty && b64 != prev) {
        final f = functions.base64toFile(b64);
        if (f != null && f.bytes != null) return Uint8List.fromList(f.bytes!);
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return null;
  }

  Future<String?> _saveBytesToGallery(Uint8List bytes) async {
    final path = '${Directory.systemTemp.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    await GallerySaver.saveImage(f.path);
    return f.path;
  }

  void _blinkShutter() {
    setState(() => _shutterBlink = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _shutterBlink = false);
    });
  }

  Future<void> _processAfterShot() async {
    final srcBytes = await _waitForShotBytes();
    if (srcBytes == null) return;

    final outBytes = await compute<Uint8List, Uint8List>(_cropResizeWorker, srcBytes);
    final saved = await _saveBytesToGallery(outBytes);
    if (!mounted) return;
    setState(() => _lastPhotoPath = saved);
  }

  void _shoot() {
    HapticFeedback.lightImpact();
    _blinkShutter();
    FFAppState().fileBase64 = '';   // reset prima dello scatto
    FFAppState().makePhoto = true;  // trigger al widget camera
    setState(() {});                // notifica
    _processAfterShot();            // background
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: brandColor,
        title: Text('Epidermys',
          style: FlutterFlowTheme.of(context).headlineMedium.override(
            font: GoogleFonts.interTight(
              fontWeight: FlutterFlowTheme.of(context).headlineMedium.fontWeight,
              fontStyle: FlutterFlowTheme.of(context).headlineMedium.fontStyle,
            ),
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        elevation: 2,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Preview
            Positioned.fill(
              child: custom_widgets.CameraPhoto(
                width: double.infinity,
                height: double.infinity,
              ),
            ),

            // Riquadro guida 1:1 (solo bordo)
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth, h = c.maxHeight;
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

            // Blink scatto
            AnimatedOpacity(
              opacity: _shutterBlink ? 1 : 0,
              duration: const Duration(milliseconds: 80),
              child: Container(color: Colors.white),
            ),

            // Thumbnail (basso sinistra)
            if (_lastPhotoPath != null)
              Positioned(
                left: 24,
                bottom: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_lastPhotoPath!),
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
    );
  }
}