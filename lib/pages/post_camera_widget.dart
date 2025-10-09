// 🔹 post_camera_widget.dart — Fotocamera POST fullscreen con ghost statico + linee verdi Mediapipe
import 'dart:io';
import 'dart:math' show sqrt, acos, pi;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👻 immagine PRE con cui generare il ghost

  const PostCameraWidget({
    super.key,
    this.guideImage,
  });

  static String routeName = 'PostCameraPage';
  static String routePath = '/postCameraPage';

  @override
  State<PostCameraWidget> createState() => _PostCameraWidgetState();
}

class _PostCameraWidgetState extends State<PostCameraWidget>
    with WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  bool _initializing = true;
  bool _shooting = false;
  String? _lastShotPath;

  Uint8List? _ghostWithLines; // ghost statico da mostrare sopra la preview

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _prepareGhost();
  }

  Future<void> _prepareGhost() async {
    if (widget.guideImage == null) return;
    try {
      final bytes = await widget.guideImage!.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      // ridimensiona a 1024x1024 per velocità
      final img.Image resized = img.copyResize(decoded, width: 1024, height: 1024);

      // converte in grigio e aumenta luminosità
      final gray = img.grayscale(resized);
      final bright = img.adjustColor(gray, brightness: 0.3, contrast: 1.3);

      // genera contorni verdi simulando Mediapipe
      final FaceDetector faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      // converte in InputImage per MLKit
      final tmpPath = '${Directory.systemTemp.path}/tmp_guide.png';
      await File(tmpPath).writeAsBytes(img.encodePng(resized));
      final input = InputImage.fromFilePath(tmpPath);

      final faces = await faceDetector.processImage(input);
      faceDetector.close();

      final paint = img.Image.from(bright);
      final green = img.ColorInt32.rgb(0, 255, 0);

      if (faces.isNotEmpty) {
        for (final face in faces) {
          for (final contour in face.contours.values) {
            for (final p in contour.points) {
              final int x = (p.x.clamp(0, paint.width - 1)).toInt();
              final int y = (p.y.clamp(0, paint.height - 1)).toInt();
              // disegna pixel più spessi (3x3)
              for (int dx = -1; dx <= 1; dx++) {
                for (int dy = -1; dy <= 1; dy++) {
                  final nx = x + dx, ny = y + dy;
                  if (nx >= 0 && nx < paint.width && ny >= 0 && ny < paint.height) {
                    paint.setPixel(nx, ny, green);
                  }
                }
              }
            }
          }
        }
      }

      // crea ghost con trasparenza
      final blended = img.adjustColor(paint, brightness: 0.2);
      final png = Uint8List.fromList(img.encodePng(blended));

      setState(() {
        _ghostWithLines = png;
      });
    } catch (e) {
      debugPrint("⚠️ Errore generazione ghost: $e");
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _initializing = false);
        return;
      }
      final frontIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final index = frontIndex >= 0 ? frontIndex : 0;
      final ctrl = CameraController(
        _cameras[index],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      await ctrl.setZoomLevel(1.0);
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      debugPrint("Camera init error: $e");
      setState(() => _initializing = false);
    }
  }

  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;
    setState(() => _shooting = true);
    try {
      final shot = await ctrl.takePicture();
      final Uint8List bytes = await File(shot.path).readAsBytes();

      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (pState.hasAccess) {
        final baseName = 'post_full_${DateTime.now().millisecondsSinceEpoch}';
        await PhotoManager.editor.saveImage(bytes, filename: '$baseName.jpg');
      }
      Navigator.pop(context, File(shot.path));
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      setState(() => _shooting = false);
    }
  }

  Widget _buildCameraPreview() {
    final ctrl = _controller;
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: Text('Fotocamera non disponibile'));
    }

    final preview = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: ctrl.value.previewSize?.height ?? 1080,
        height: ctrl.value.previewSize?.width ?? 1440,
        child: CameraPreview(ctrl),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: preview),

        // 👻 Ghost con linee verdi statiche
        if (_ghostWithLines != null)
          Opacity(
            opacity: 0.45,
            child: Image.memory(
              _ghostWithLines!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // ⚖️ Livella verticale
        buildLivellaVerticaleOverlay(topOffsetPx: 65.0),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_shooting;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: canShoot ? _takeAndSavePicture : null,
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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraPreview()),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }
}

// ⚖️ Livella verticale
Widget buildLivellaVerticaleOverlay({
  double okThresholdDeg = 1.5,
  double topOffsetPx = 65.0,
}) {
  return Positioned(
    top: topOffsetPx,
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
            final g = sqrt(ax * ax + ay * ay + az * az);
            if (g > 0) {
              double c = (-az) / g;
              c = c.clamp(-1.0, 1.0);
              angleDeg = (acos(c) * 180.0 / pi) - 90.0;
            }
          }
          final bool ok = angleDeg.abs() <= okThresholdDeg;
          final color = ok ? Colors.greenAccent : Colors.redAccent;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${angleDeg.toStringAsFixed(1)}°",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          );
        },
      ),
    ),
  );
}
