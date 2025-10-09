// 🔹 post_camera_widget.dart — Fotocamera POST fullscreen con Mediapipe, ghost PRE e fix iOS 18 / Flutter 3.22

import 'dart:io';
import 'dart:math' show Point, sqrt, acos, pi;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class PostCameraWidget extends StatefulWidget {
  final File? guideImage; // 👻 immagine PRE come ghost

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
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _shooting = false;
  String? _lastShotPath;

  // 🔹 Mediapipe FaceDetector
  late final FaceDetector _faceDetector;
  CustomPainter? _faceLandmarksPainter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _initFaceDetector();
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
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
      _cameraIndex = frontIndex >= 0 ? frontIndex : 0;
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
      await ctrl.setZoomLevel(1.0);
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
      _startStream();
    } catch (e) {
      debugPrint('Controller start error: $e');
      await ctrl.dispose();
      setState(() => _initializing = false);
    }
  }

  // 🔹 Stream per Mediapipe (linee verdi)
  void _startStream() {
    _controller?.startImageStream((CameraImage image) async {
      try {
        final WriteBuffer buffer = WriteBuffer();
        for (final Plane plane in image.planes) {
          buffer.putUint8List(plane.bytes);
        }
        final bytes = buffer.done().buffer.asUint8List();

        final camera = _cameras[_cameraIndex];
        final rotation =
            InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
                InputImageRotation.rotation0deg;
        final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

        final metadata = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        );

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );

        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isNotEmpty) {
          setState(() {
            _faceLandmarksPainter = _FacePainter(
              faces: faces,
              imageSize: metadata.size,
            );
          });
        }
      } catch (e) {
        debugPrint("⚠️ Errore stream camera: $e");
      }
    });
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

  // ====== Scatto + salvataggio ======
  Future<void> _takeAndSavePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _shooting) return;

    setState(() => _shooting = true);
    try {
      final bool isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;

      final XFile shot = await ctrl.takePicture();
      final Uint8List origBytes = await File(shot.path).readAsBytes();
      img.Image? original = img.decodeImage(origBytes);
      if (original == null) throw Exception('Decodifica immagine fallita');

      if (isFront) {
        original = img.flipHorizontal(original);
      }

      // 🔹 Nessun crop: salva l'immagine intera
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(original));

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
          'post_full_${DateTime.now().millisecondsSinceEpoch}';
      final AssetEntity? asset = await PhotoManager.editor.saveImage(
        pngBytes,
        filename: '$baseName.png',
      );
      if (asset == null) throw Exception('Salvataggio PNG fallito');

      final Directory tempDir =
          await Directory.systemTemp.createTemp('epi_post');
      final String newPath = '${tempDir.path}/$baseName.png';
      await File(newPath).writeAsBytes(pngBytes);
      _lastShotPath = newPath;

      debugPrint('✅ Foto salvata full-res — ${original.width}x${original.height}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto salvata a pieno schermo')),
        );
        setState(() {});
        Navigator.pop(context, newPath);
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

  // ====== Preview FULLSCREEN con Mediapipe + Ghost ======
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

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: preview),

        // 👻 Ghost PRE trasparente
        if (widget.guideImage != null)
          Opacity(
            opacity: 0.4,
            child: Image.file(
              widget.guideImage!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // 🟢 Linee Mediapipe (invariato)
        if (_faceLandmarksPainter != null)
          CustomPaint(painter: _faceLandmarksPainter),

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

// ⚖️ Livella verticale
Widget buildLivellaVerticaleOverlay(
    {double okThresholdDeg = 1.0, double topOffsetPx = 65.0}) {
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
          final Color bigColor = ok ? Colors.greenAccent : Colors.redAccent;

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
                color: bigColor,
              ),
            ),
          );
        },
      ),
    ),
  );
}

// 🟢 Disegno linee verdi Mediapipe
class _FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  _FacePainter({required this.faces, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final face in faces) {
      final contour = face.contours[FaceContourType.face];
      if (contour != null) {
        for (int i = 0; i < contour.points.length - 1; i++) {
          final p1 = _scalePoint(contour.points[i], size);
          final p2 = _scalePoint(contour.points[i + 1], size);
          canvas.drawLine(p1, p2, paint);
        }
      }
    }
  }

  Offset _scalePoint(Point<int> point, Size size) {
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    return Offset(point.x * scaleX, point.y * scaleY);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
