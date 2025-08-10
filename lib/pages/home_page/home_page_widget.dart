// === IMPORT FLUTTERFLOW ===
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/flutter_flow/custom_functions.dart' as functions;
import 'package:custom_camera_component/index.dart'; // <-- usa il nome nel pubspec

import 'dart:async'; // ✅ per StreamSubscription
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
import 'package:sensors_plus/sensors_plus.dart'; // <-- per pitch/roll
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

// ====== PARAMETRI RAPIDI ======
const double squareOffsetY = -0.25;  // -1 su, 0 centro, 1 giù
const double squareScale   = 0.9;    // grandezza riquadro guida
const Color  brandColor    = Color(0xFF1F4E78);

// TOLLERANZE (stile Face ID)
const double phoneAngleTol = 3.0; // gradi pitch/roll ok
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

  // sensori
  double _pitch = 0.0; // avanti/indietro (+ su, - giù)
  double _roll  = 0.0; // sinistra/destra (+ dx, - sx)
  StreamSubscription<AccelerometerEvent>? _accSub; // ✅ tipizzato

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());

    // stream accelerometro -> calcolo pitch/roll semplici
    _accSub = accelerometerEventStream().listen((e) {
      final ax = e.x.toDouble();
      final ay = e.y.toDouble();
      final az = e.z.toDouble();
      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi;
      final roll  = math.atan2(ay, az) * 180 / math.pi;
      if (mounted) {
        setState(() {
          _pitch = pitch;
          _roll  = roll;
        });
      }
    });
  }

  @override
  void dispose() {
    _accSub?.cancel();
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
    final resized = img.copyResize(
      cropped, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);
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
        title: Text(
          'Epidermys',
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
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            final side = (w < h ? w : h) * squareScale;
            final squareLeft = (w - side) / 2;
            final squareTop  = (h - side) / 2 + (h * squareOffsetY / 2);

            return Stack(
              children: [
                // === 1) PREVIEW FOTOCAMERA FULL SCREEN ===
                Positioned.fill(
                  child: custom_widgets.CameraPhoto(
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),

                // === 2) OVERLAY TRASPARENTE (solo linee/bolle) ===
                // BORDO + GUIDE OCCHI
                Positioned(
                  left: squareLeft, top: squareTop, width: side, height: side,
                  child: CustomPaint(
                    painter: _SquarePainter(
                      ok: _pitch.abs() <= phoneAngleTol && _roll.abs() <= phoneAngleTol,
                    ),
                  ),
                ),

                // CHIP NUMERICI PITCH/ROLL
                Positioned(
                  left: squareLeft + 8,
                  right: (w - (squareLeft + side)) + 8,
                  top: squareTop + 8,
                  child: _LevelBar(
                    pitch: _pitch, roll: _roll, tol: phoneAngleTol,
                  ),
                ),

                // BOLLA ORIZZONTALE (ROLL)
                Positioned(
                  left: squareLeft + 16,
                  width: side - 32,
                  top: squareTop + side / 2 - 10,
                  height: 20,
                  child: _BubbleLevelHorizontal(
                    rollDeg: _roll, tol: phoneAngleTol,
                  ),
                ),

                // BOLLA VERTICALE (PITCH)
                Positioned(
                  left: squareLeft + side / 2 - 10,
                  top: squareTop + 16,
                  height: side - 32,
                  width: 20,
                  child: _BubbleLevelVertical(
                    pitchDeg: _pitch, tol: phoneAngleTol,
                  ),
                ),

                // === 3) FLASH SENZA OPACITY (niente black screen) ===
                Visibility(
                  visible: _shutterBlink,
                  child: Container(color: Colors.white),
                ),

                // === 4) THUMBNAIL (basso sinistra)
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

                // === 5) PULSANTE SCATTO ===
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
            );
          },
        ),
      ),
    );
  }
}

/* ================= PITTORI/OVERLAY ================= */

class _SquarePainter extends CustomPainter {
  final bool ok;
  _SquarePainter({required this.ok});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // bordo quadrato (verde quando ok)
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ok ? Colors.greenAccent : Colors.white;
    canvas.drawRect(rect, border);

    // bande "occhi" (40% e 55%)
    final y1 = rect.top + rect.height * 0.40;
    final y2 = rect.top + rect.height * 0.55;
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white70;
    canvas.drawLine(Offset(rect.left, y1), Offset(rect.right, y1), guide);
    canvas.drawLine(Offset(rect.left, y2), Offset(rect.right, y2), guide);

    // crocetta al centro
    final c = rect.center;
    canvas.drawLine(Offset(c.dx - 12, c.dy), Offset(c.dx + 12, c.dy), guide);
    canvas.drawLine(Offset(c.dx, c.dy - 12), Offset(c.dx, c.dy + 12), guide);
  }

  @override
  bool shouldRepaint(covariant _SquarePainter oldDelegate) => oldDelegate.ok != ok;
}

/* ---------- Livella numerica (chip Pitch/Roll) ---------- */

class _LevelBar extends StatelessWidget {
  final double pitch;
  final double roll;
  final double tol;

  const _LevelBar({required this.pitch, required this.roll, required this.tol});

  @override
  Widget build(BuildContext context) {
    final ok = pitch.abs() <= tol && roll.abs() <= tol;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip('Pitch', pitch, ok),
        const SizedBox(width: 8),
        _chip('Roll', roll, ok),
      ],
    );
  }

  Widget _chip(String label, double val, bool ok) {
    final txt = '${val.toStringAsFixed(1)}°';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? Colors.greenAccent : Colors.white54),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 6),
          Text(txt, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/* ---------- Livella a bolla: ORIZZONTALE (ROLL) ---------- */

class _BubbleLevelHorizontal extends StatelessWidget {
  final double rollDeg; // negativo=sinistra, positivo=destra
  final double tol;

  const _BubbleLevelHorizontal({required this.rollDeg, required this.tol});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleLevelHorizontalPainter(rollDeg: rollDeg, tol: tol),
    );
  }
}

class _BubbleLevelHorizontalPainter extends CustomPainter {
  final double rollDeg;
  final double tol;

  _BubbleLevelHorizontalPainter({required this.rollDeg, required this.tol});

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = 6.0;
    final radius = 10.0;
    final barRect = RRect.fromRectXY(
      Rect.fromLTWH(0, (size.height - barHeight) / 2, size.width, barHeight),
      3, 3,
    );

    final ok = rollDeg.abs() <= tol;
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = ok ? Colors.greenAccent.withOpacity(0.75) : Colors.white70;

    canvas.drawRRect(barRect, barPaint);

    const maxDeg = 15.0;
    final clamped = rollDeg.clamp(-maxDeg, maxDeg);
    final t = (clamped + maxDeg) / (2 * maxDeg); // 0..1
    final cx = t * size.width;
    final cy = size.height / 2;

    final bubble = Paint()..color = Colors.black.withOpacity(0.65);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ok ? Colors.greenAccent : Colors.white;

    canvas.drawCircle(Offset(cx, cy), radius, bubble);
    canvas.drawCircle(Offset(cx, cy), radius, border);

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withOpacity(0.7);
    final midX = size.width / 2;
    canvas.drawLine(Offset(midX, cy - 10), Offset(midX, cy + 10), tick);
  }

  @override
  bool shouldRepaint(covariant _BubbleLevelHorizontalPainter oldDelegate) =>
      oldDelegate.rollDeg != rollDeg || oldDelegate.tol != tol;
}

/* ---------- Livella a bolla: VERTICALE (PITCH) ---------- */

class _BubbleLevelVertical extends StatelessWidget {
  final double pitchDeg; // negativo=giù, positivo=su
  final double tol;

  const _BubbleLevelVertical({required this.pitchDeg, required this.tol});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleLevelVerticalPainter(pitchDeg: pitchDeg, tol: tol),
    );
  }
}

class _BubbleLevelVerticalPainter extends CustomPainter {
  final double pitchDeg;
  final double tol;

  _BubbleLevelVerticalPainter({required this.pitchDeg, required this.tol});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 6.0;
    final radius = 10.0;
    final barRect = RRect.fromRectXY(
      Rect.fromLTWH((size.width - barWidth) / 2, 0, barWidth, size.height),
      3, 3,
    );

    final ok = pitchDeg.abs() <= tol;
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = ok ? Colors.greenAccent.withOpacity(0.75) : Colors.white70;

    canvas.drawRRect(barRect, barPaint);

    const maxDeg = 15.0;
    final clamped = pitchDeg.clamp(-maxDeg, maxDeg);
    final t = (maxDeg - clamped) / (2 * maxDeg); // 0..1 (0 alto, 1 basso)
    final cx = size.width / 2;
    final cy = t * size.height;

    final bubble = Paint()..color = Colors.black.withOpacity(0.65);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ok ? Colors.greenAccent : Colors.white;

    canvas.drawCircle(Offset(cx, cy), radius, bubble);
    canvas.drawCircle(Offset(cx, cy), radius, border);

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withOpacity(0.7);
    final midY = size.height / 2;
    canvas.drawLine(Offset(cx - 10, midY), Offset(cx + 10, midY), tick);
  }

  @override
  bool shouldRepaint(covariant _BubbleLevelVerticalPainter oldDelegate) =>
      oldDelegate.pitchDeg != pitchDeg || oldDelegate.tol != tol;
}