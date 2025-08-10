import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show WriteBuffer; // per comporre bytes YUV
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'overlay/guide_overlay.dart';
import 'utils/geometry.dart';

class GuidedCapturePage extends StatefulWidget {
  const GuidedCapturePage({super.key});

  @override
  State<GuidedCapturePage> createState() => _GuidedCapturePageState();
}

class _GuidedCapturePageState extends State<GuidedCapturePage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;

  // Sensori
  double _phonePitch = 0;
  double _phoneRoll = 0;
  StreamSubscription? _accSub;

  // ML Kit
  late final FaceDetector _detector;
  Face? _lastFace;
  Rect? _lastFaceRectPreview;

  // Layout
  Size? _previewWidgetSize;
  Rect? _squareRectOnPreview;

  // Stato
  bool _streaming = false;
  bool _busyCapturing = false;
  DateTime? _allGreenSince;
  File? _lastThumb;

  // Selfie/Specchio anteprima
  bool _mirrorPreview = true; // anteprima specchiata quando frontale

  // Soglie
  static const phoneAngleTol = 3.0;
  static const faceRollTol  = 3.0;
  static const faceYawTol   = 5.0;
  static const facePitchTol = 5.0;
  static const stableMs     = 500;
  static const bboxMin = 0.70;
  static const bboxMax = 0.80;

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: false,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
      ),
    );
    _init();
  }

  Future<void> _init() async {
    _cameras = await availableCameras();
    final front = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    await _startWithCamera(front);

    _accSub = accelerometerEventStream().listen((e) {
      final ax = e.x.toDouble();
      final ay = e.y.toDouble();
      final az = e.z.toDouble();
      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi;
      final roll  = math.atan2(ay, az) * 180 / math.pi;
      setState(() {
        _phonePitch = pitch;
        _phoneRoll = roll;
      });
    });

    setState(() => _initializing = false);
  }

  Future<void> _startWithCamera(CameraDescription cam) async {
    _streaming = false;
    await _controller?.dispose();

    _controller = CameraController(
      cam,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    // Selfie: anteprima specchiata se frontale
    _mirrorPreview = cam.lensDirection == CameraLensDirection.front;

    _streaming = true;
    _controller!.startImageStream(_onImage);
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty) return;
    final current = _controller?.description;
    CameraDescription? next;

    if (_cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
        _cameras.any((c) => c.lensDirection == CameraLensDirection.back)) {
      next = current?.lensDirection == CameraLensDirection.front
          ? _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back)
          : _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    } else {
      next = current ?? _cameras.first;
    }

    await _startWithCamera(next);
  }

  Future<void> _onImage(CameraImage image) async {
    if (!_streaming || _busyCapturing) return;
    if (_previewWidgetSize == null) return;

    try {
      final inputImage = _toInputImage(image, _controller!.description.sensorOrientation);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        setState(() {
          _lastFace = null;
          _lastFaceRectPreview = null;
        });
        _resetGreenTimer();
        return;
      }

      Face face = faces.reduce((a, b) =>
          a.boundingBox.size.width * a.boundingBox.size.height >
                  b.boundingBox.size.width * b.boundingBox.size.height
              ? a
              : b);

      final cam = _controller!;
      final previewSize = _previewWidgetSize!;
      final cameraImageSize = Size(image.width.toDouble(), image.height.toDouble());
      final rotatedImageSize = isRotation90or270(cam.description.sensorOrientation)
          ? Size(cameraImageSize.height, cameraImageSize.width)
          : cameraImageSize;

      final rectInPreview = mapImageRectToPreview(
        imageRect: face.boundingBox,
        imageSize: rotatedImageSize,
        previewSize: previewSize,
        fit: BoxFit.cover,
        mirrorPreview: _mirrorPreview,
      );

      setState(() {
        _lastFace = face;
        _lastFaceRectPreview = rectInPreview;
      });

      _checkAndMaybeCapture();
    } catch (_) {
      // ignora errori sporadici
    }
  }

  // ✅ Corretto per google_mlkit_face_detection 0.11.x (niente planeData)
  InputImage _toInputImage(CameraImage image, int sensorOrientation) {
    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }
    final bytesAll = bytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    return InputImage.fromBytes(
      bytes: bytesAll,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void _checkAndMaybeCapture() async {
    if (_busyCapturing || _squareRectOnPreview == null || _lastFace == null || _lastFaceRectPreview == null) return;

    final phoneOk = _phoneOk();
    final faceOk  = _faceAnglesOk(_lastFace!);
    final scaleOk = _faceScaleOk(_lastFaceRectPreview!, _squareRectOnPreview!);
    final centerOk = _faceCenterOk(_lastFaceRectPreview!, _squareRectOnPreview!);

    final allGreen = phoneOk && faceOk && scaleOk && centerOk;
    if (!allGreen) {
      _resetGreenTimer();
      return;
    }

    final now = DateTime.now();
    _allGreenSince ??= now;
    if (now.difference(_allGreenSince!).inMilliseconds < stableMs) return;

    _allGreenSince = null;
    await _doCaptureAndCrop();
  }

  bool _phoneOk() => _phonePitch.abs() <= phoneAngleTol && _phoneRoll.abs() <= phoneAngleTol;

  bool _faceAnglesOk(Face f) {
    final pitch = f.headEulerAngleX ?? 999;
    final yaw   = f.headEulerAngleY ?? 999;
    final roll  = f.headEulerAngleZ ?? 999;
    return pitch.abs() <= facePitchTol && yaw.abs() <= faceYawTol && roll.abs() <= faceRollTol;
  }

  bool _faceScaleOk(Rect faceRect, Rect square) {
    final ratio = faceRect.height / square.width;
    return ratio >= bboxMin && ratio <= bboxMax;
  }

  bool _faceCenterOk(Rect faceRect, Rect square) => square.contains(faceRect.center);

  void _resetGreenTimer() => _allGreenSince = null;

  Future<void> _doCaptureAndCrop() async {
    if (_busyCapturing) return;
    _busyCapturing = true;
    try {
      final cam = _controller!;
      final xFile = await cam.takePicture();

      final bytes = await File(xFile.path).readAsBytes();
      final decoded = img.decodeImage(bytes)!;
      final imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      final previewSize = _previewWidgetSize!;

      final cropRectInImage = mapPreviewRectToImage(
        overlayInPreview: _squareRectOnPreview!,
        previewSize: previewSize,
        imageSize: imageSize,
        fit: BoxFit.cover,
        mirrorPreview: _mirrorPreview,
      );

      final cropped = cropSafe(decoded, cropRectInImage);
      final resized = img.copyResize(cropped, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.png';
      final outBytes = img.encodePng(resized);
      await File(outPath).writeAsBytes(outBytes);

      setState(() {
        _lastThumb = File(outPath);
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Scatto salvato (1024×1024)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore scatto: $e')),
        );
      }
    } finally {
      _busyCapturing = false;
    }
  }

  /// Scatto manuale (sempre consentito)
  Future<void> _manualShutter() async {
    await _doCaptureAndCrop();
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          _previewWidgetSize = previewSize;

          final side = math.min(previewSize.width, previewSize.height) * 0.86;
          final left = (previewSize.width - side) / 2;
          final top  = (previewSize.height - side) / 2;
          final square = Rect.fromLTWH(left, top, side, side);
          _squareRectOnPreview = square;

          final preview = CameraPreview(_controller!);

          return Stack(
            children: [
              // Preview camera (specchiata se selfie)
              Positioned.fill(
                child: _mirrorPreview
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                        child: preview,
                      )
                    : preview,
              ),

              // Overlay guida
              Positioned.fill(
                child: GuideOverlay(
                  square: square,
                  phonePitch: _phonePitch,
                  phoneRoll: _phoneRoll,
                  faceRect: _lastFaceRectPreview,
                  faceAngles: (
                    _lastFace?.headEulerAngleX,
                    _lastFace?.headEulerAngleY,
                    _lastFace?.headEulerAngleZ
                  ),
                  thresholds: const GuideThresholds(
                    phoneAngleTol: phoneAngleTol,
                    faceRollTol: faceRollTol,
                    faceYawTol: faceYawTol,
                    facePitchTol: facePitchTol,
                    bboxMin: bboxMin,
                    bboxMax: bboxMax,
                  ),
                ),
              ),

              // Thumbnail in basso a sinistra
              if (_lastThumb != null)
                Positioned(
                  left: 16,
                  bottom: 24,
                  child: GestureDetector(
                    onTap: () {
                      // TODO: apri galleria interna se serve
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _lastThumb!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

              // Pulsante SCATTO MANUALE (centro basso)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _busyCapturing ? null : _manualShutter,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _busyCapturing ? Colors.white24 : Colors.white,
                          width: 4,
                        ),
                        color: Colors.white10,
                      ),
                    ),
                  ),
                ),
              ),

              // Pulsante SWITCH CAMERA (basso a destra)
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

              // Pulsante back (alto a sinistra)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}