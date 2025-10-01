import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// importa AnalysisPreview per analisi sul server
import 'package:custom_camera_component/pages/distanza_cm_overlay.dart';
import 'package:custom_camera_component/pages/level_guide.dart';

class PrePostWidget extends StatefulWidget {
  final String? preFile;   // Filename analisi PRE nel DB
  final String? postFile;  // Filename analisi POST nel DB

  const PrePostWidget({
    super.key,
    this.preFile,
    this.postFile,
  });

  @override
  State<PrePostWidget> createState() => _PrePostWidgetState();
}

class _PrePostWidgetState extends State<PrePostWidget> {
  File? preImage;
  File? postImage;
  Map<String, dynamic>? compareData;

  String? preFile;
  String? postFile;

  @override
  void initState() {
    super.initState();
    preFile = widget.preFile;
    postFile = widget.postFile;
    if (preFile != null && postFile != null) {
      _loadCompareResults();
    }
  }

  // === Carica risultati comparazione dal server ===
  Future<void> _loadCompareResults() async {
    if (preFile == null || postFile == null) {
      debugPrint("⚠️ preFile o postFile mancanti, skip comparazione");
      return;
    }

    final url = Uri.parse(
        "http://46.101.223.88:5000/compare_from_db?pre_file=$preFile&post_file=$postFile");
    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          compareData = jsonDecode(resp.body);
        });
        debugPrint("✅ Dati comparazione ricevuti: $compareData");
      } else {
        debugPrint("❌ Errore server: ${resp.body}");
      }
    } catch (e) {
      debugPrint("❌ Errore richiesta: $e");
    }
  }

  // === Seleziona PRE dalla galleria (lookup su server per filename DB) ===
  Future<void> _pickPreImage() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permesso galleria negato")),
      );
      return;
    }

    final List<AssetPathEntity> paths =
        await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty) return;

    final List<AssetEntity> media =
        await paths.first.getAssetListPaged(page: 0, size: 100);
    if (media.isEmpty) return;

    final file = await showDialog<File?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Seleziona foto PRE"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: media.length,
            itemBuilder: (context, index) {
              return FutureBuilder<Uint8List?>(
                future: media[index]
                    .thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.data != null) {
                    return GestureDetector(
                      onTap: () async {
                        final File? f = await media[index].file;
                        if (f != null && context.mounted) {
                          Navigator.pop(context, f);
                        }
                      },
                      child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                    );
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              );
            },
          ),
        ),
      ),
    );

    if (file != null) {
      setState(() {
        preImage = file;
      });

      // 🔹 Usa timestamp per cercare nel DB il filename corretto
      final ts = file.lastModifiedSync().millisecondsSinceEpoch;

      try {
        final url =
            Uri.parse("http://46.101.223.88:5000/find_by_timestamp?ts=$ts");
        final resp = await http.get(url);

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final serverFilename = data["filename"];

          if (serverFilename != null) {
            setState(() {
              preFile = serverFilename;
            });
            debugPrint("✅ PRE associato a record DB: $serverFilename");
          } else {
            // fallback se non trovato
            setState(() {
              preFile = path.basename(file.path);
            });
            debugPrint("⚠️ PRE senza match DB, uso filename locale");
          }
        }
      } catch (e) {
        debugPrint("❌ Errore lookup PRE: $e");
        setState(() {
          preFile = path.basename(file.path);
        });
      }
    }
  }

  // === Scatta POST con camera, analizza e torna indietro ===
  Future<void> _capturePostImage() async {
    if (preFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Devi avere un PRE prima del POST")),
      );
      return;
    }

    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    final result = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraOverlayPage(
          cameras: cameras,
          initialCamera: firstCamera,
          guideImage: preImage!,
        ),
      ),
    );

    if (result != null) {
      final analyzed = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisPreview(
            imagePath: result.path,
            mode: "prepost", // il server userà prefix POST_
          ),
        ),
      );

      if (analyzed != null) {
        final overlayPath = analyzed["overlay_path"] as String?;
        final newPostFile = analyzed["filename"] as String?;

        if (overlayPath != null) {
          setState(() {
            postImage = File(overlayPath);
          });
          debugPrint("✅ Overlay POST salvato: $overlayPath");
        }
        if (newPostFile != null) {
          setState(() {
            postFile = newPostFile;
          });
          await _loadCompareResults();
        }
      }
    }
  }

  // === Conferma per rifare la foto POST ===
  Future<void> _confirmRetakePost() async {
    final bool? retake = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rifare la foto POST?"),
        content: const Text("Vuoi davvero scattare di nuovo la foto POST?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annulla"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Rifai foto"),
          ),
        ],
      ),
    );

    if (retake == true) {
      await _capturePostImage();
    }
  }

  // === Widget barra percentuale ===
  Widget _buildBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ${value.toStringAsFixed(2)}%"),
        LinearProgressIndicator(
          value: value / 100,
          backgroundColor: Colors.grey[300],
          color: color,
          minHeight: 12,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double boxSize = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(title: const Text("Pre/Post")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GestureDetector(
              onTap: preImage == null ? _pickPreImage : null,
              child: Container(
                width: boxSize,
                height: boxSize,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: preImage == null
                    ? const Center(
                        child: Icon(Icons.add, size: 80, color: Colors.blue),
                      )
                    : Image.file(preImage!, fit: BoxFit.cover),
              ),
            ),
            GestureDetector(
              onTap: postImage == null ? _capturePostImage : _confirmRetakePost,
              child: Container(
                width: boxSize,
                height: boxSize,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: postImage == null
                    ? const Center(
                        child: Icon(Icons.add, size: 80, color: Colors.green),
                      )
                    : Image.file(postImage!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),

            // === Risultati comparazione ===
            if (compareData != null) ...[
              if (compareData!["macchie"] != null)
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("📊 Percentuali Macchie",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        _buildBar(
                            "Pre",
                            compareData!["macchie"]["perc_pre"] ?? 0.0,
                            Colors.green),
                        _buildBar(
                            "Post",
                            compareData!["macchie"]["perc_post"] ?? 0.0,
                            Colors.blue),
                        Builder(
                          builder: (_) {
                            final double pre =
                                (compareData!["macchie"]["perc_pre"] ?? 0.0)
                                    .toDouble();
                            final double post =
                                (compareData!["macchie"]["perc_post"] ?? 0.0)
                                    .toDouble();

                            double diffPerc = 0.0;
                            if (pre > 0) {
                              diffPerc = ((post - pre) / pre) * 100;
                            }

                            return _buildBar(
                              "Differenza",
                              diffPerc.abs(),
                              diffPerc <= 0 ? Colors.green : Colors.red,
                            );
                          },
                        ),
                        Text(
                            "Numero PRE: ${compareData!["macchie"]["numero_macchie_pre"]}"),
                        Text(
                            "Numero POST: ${compareData!["macchie"]["numero_macchie_post"]}"),
                      ],
                    ),
                  ),
                ),

              if (compareData!["pori"] != null)
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("📊 Pori dilatati (rossi)",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        _buildBar(
                            "Pre",
                            compareData!["pori"]["perc_pre_dilatati"] ?? 0.0,
                            Colors.green),
                        _buildBar(
                            "Post",
                            compareData!["pori"]["perc_post_dilatati"] ?? 0.0,
                            Colors.blue),
                        _buildBar(
                            "Differenza",
                            (compareData!["pori"]["perc_diff_dilatati"] ?? 0.0)
                                .abs(),
                            (compareData!["pori"]["perc_diff_dilatati"] ?? 0.0) <=
                                    0
                                ? Colors.green
                                : Colors.red),
                        Text(
                            "PRE → Normali: ${compareData!["pori"]["num_pori_pre"]["normali"]}, Borderline: ${compareData!["pori"]["num_pori_pre"]["borderline"]}, Dilatati: ${compareData!["pori"]["num_pori_pre"]["dilatati"]}"),
                        Text(
                            "POST → Normali: ${compareData!["pori"]["num_pori_post"]["normali"]}, Borderline: ${compareData!["pori"]["num_pori_post"]["borderline"]}, Dilatati: ${compareData!["pori"]["num_pori_post"]["dilatati"]}"),
                      ],
                    ),
                  ),
                ),
            ]
          ],
        ),
      ),
    );
  }
}

// === CameraOverlayPage aggiornata come Home ===
class CameraOverlayPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final CameraDescription initialCamera;
  final File guideImage;

  const CameraOverlayPage({
    super.key,
    required this.cameras,
    required this.initialCamera,
    required this.guideImage,
  });

  @override
  State<CameraOverlayPage> createState() => _CameraOverlayPageState();
}

class _CameraOverlayPageState extends State<CameraOverlayPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  late CameraDescription currentCamera;
  bool _shooting = false;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  double _lastIpdPx = 0.0;
  final double _ipdMm = 63.0;
  final double _targetMmPerPx = 0.117;
  bool _scaleOk = false;
  DateTime _lastProc = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    currentCamera = widget.initialCamera;
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _controller?.dispose();
    _controller = CameraController(
      currentCamera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initializeControllerFuture = _controller!.initialize().then((_) async {
      await _controller!.setFlashMode(FlashMode.off);
      await _controller!.startImageStream(_processCameraImage);
    });
    if (mounted) setState(() {});
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastProc).inMilliseconds < 300) return;
    _lastProc = now;

    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final rotation = _rotationFromSensor(_controller!.description.sensorOrientation);
      final inputImage = _inputImageFromCameraImage(image, rotation);

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return;

      final f = faces.first;
      final left = f.landmarks[FaceLandmarkType.leftEye];
      final right = f.landmarks[FaceLandmarkType.rightEye];
      if (left == null || right == null) return;

      final dx = (left.position.x - right.position.x);
      final dy = (left.position.y - right.position.y);
      final distPx = math.sqrt(dx * dx + dy * dy);

      final tgt = _ipdMm / _targetMmPerPx;
      final minT = tgt * 0.95;
      final maxT = tgt * 1.05;
      setState(() {
        _lastIpdPx = distPx;
        _scaleOk = (distPx >= minT && distPx <= maxT);
      });
    } catch (_) {}
  }

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
      CameraImage image, InputImageRotation rotation) {
    final allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

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

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      if (_shooting) return;
      setState(() => _shooting = true);

      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      if (!mounted) return;

      File file = File(image.path);

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded != null) {
        final side =
            decoded.width < decoded.height ? decoded.width : decoded.height;
        final x = (decoded.width - side) ~/ 2;
        final y = (decoded.height - side) ~/ 2;
        img.Image cropped =
            img.copyCrop(decoded, x: x, y: y, width: side, height: side);
        img.Image resized = img.copyResize(cropped, width: 1024, height: 1024);

        file = await file.writeAsBytes(img.encodePng(resized));
      }

      Navigator.pop(context, file);
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      setState(() => _shooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool isFront =
        _controller!.description.lensDirection == CameraLensDirection.front;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_controller!),
              LayoutBuilder(
                builder: (context, constraints) {
                  final shortSide =
                      math.min(constraints.maxWidth, constraints.maxHeight);

                  double squareSize;
                  if (_lastIpdPx > 0) {
                    final mmPerPxAttuale = _ipdMm / _lastIpdPx;
                    final scalaFattore = mmPerPxAttuale / _targetMmPerPx;
                    squareSize =
                        (shortSide / scalaFattore).clamp(300.0, shortSide);
                  } else {
                    squareSize = shortSide * 0.70;
                  }

                  final frameColor =
                      _scaleOk ? Colors.green : Colors.yellow.withOpacity(0.95);

                  return Stack(
                    children: [
                      Align(
                        alignment: const Alignment(0, -0.3),
                        child: Container(
                          width: squareSize,
                          height: squareSize,
                          decoration: BoxDecoration(
                            border: Border.all(color: frameColor, width: 4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      Align(
                        alignment: const Alignment(0, -0.3),
                        child: Opacity(
                          opacity: 0.3,
                          child: Image.file(widget.guideImage,
                              width: squareSize, height: squareSize),
                        ),
                      ),
                      buildDistanzaCmOverlay(
                        ipdPx: _lastIpdPx,
                        ipdMm: _ipdMm,
                        targetMmPerPx: _targetMmPerPx,
                        alignY: -0.05,
                        mode: "prepost",
                        isFrontCamera: isFront,
                      ),
                      Align(
                        alignment: const Alignment(0, -0.3),
                        child: _buildLivellaOrizzontale3Linee(
                          width: math.max(squareSize * 0.82, 300.0),
                          height: 62,
                          okThresholdDeg: 1.0,
                        ),
                      ),
                      buildLivellaVerticaleOverlay(
                        mode: null,
                        topOffsetPx: 80.0,
                      ),
                    ],
                  );
                },
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: GestureDetector(
                    onTap: _takePicture,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// === Livella orizzontale identica a Home ===
Widget _buildLivellaOrizzontale3Linee({
  required double width,
  required double height,
  double okThresholdDeg = 1.0,
}) {
  Widget _segment(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h),
        ),
      );

  return StreamBuilder<AccelerometerEvent>(
    stream: accelerometerEventStream(),
    builder: (context, snap) {
      double rollDeg = 0.0;
      if (snap.hasData) {
        final ax = snap.data!.x;
        final ay = snap.data!.y;
        rollDeg = math.atan2(ax, ay) * 180.0 / math.pi;
      }

      final bool isOk = rollDeg.abs() <= okThresholdDeg;
      final Color lineColor = isOk ? Colors.greenAccent : Colors.white;

      final double topRot = (-rollDeg.abs()) * math.pi / 180 / 1.2;
      final double botRot = (rollDeg.abs()) * math.pi / 180 / 1.2;
      final double midRot = (rollDeg) * math.pi / 180;

      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isOk ? Colors.greenAccent : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Transform.rotate(
              angle: topRot,
              child: _segment(width - 40, 2, lineColor),
            ),
            Transform.rotate(
              angle: midRot,
              child: _segment(width - 20, 3, lineColor),
            ),
            Transform.rotate(
              angle: botRot,
              child: _segment(width - 40, 2, lineColor),
            ),
          ],
        ),
      );
    },
  );
}