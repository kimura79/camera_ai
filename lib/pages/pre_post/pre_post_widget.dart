import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:sensors_plus/sensors_plus.dart';

// importa AnalysisPreview per analisi sul server
import '../analysis_preview.dart';

// === ENUM per modalità ===
enum CaptureMode { volto, particolare }

// === Overlay distanza cm (da distanza.txt) ===
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,
  double alignY = 0.4,
  CaptureMode mode = CaptureMode.volto,
}) {
  String testo;
  Color borderColor = Colors.yellow;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    if (mode == CaptureMode.volto) {
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
      if (distCm > 5 && distCm < 100) {
        testo = '${distCm.toStringAsFixed(1)} cm';
      } else {
        testo = '— cm';
      }
      borderColor = Colors.green;
    } else {
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;
      final distanzaCm = (larghezzaRealeMm / 10.0) * 2.0;
      if (distanzaCm > 5 && distanzaCm < 50) {
        testo = '${distanzaCm.toStringAsFixed(1)} cm';
      } else {
        testo = '— cm';
      }
      if ((distanzaCm - 12.0).abs() <= 1.0) {
        borderColor = Colors.green;
      }
    }
  }

  return Align(
    alignment: Alignment(0, alignY),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2.0),
      ),
      child: Text(
        testo,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

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

  // 🔹 Variabili PRE
  double? preAngle;
  double? preDistance;

  @override
  void initState() {
    super.initState();
    preFile = widget.preFile;
    postFile = widget.postFile;
    if (preFile != null && postFile != null) {
      _loadCompareResults();
    }
  }

  // === Carica comparazione ===
  Future<void> _loadCompareResults() async {
    if (preFile == null || postFile == null) return;
    final url = Uri.parse(
        "http://46.101.223.88:5000/compare_from_db?pre_file=$preFile&post_file=$postFile");
    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          compareData = jsonDecode(resp.body);
        });
      }
    } catch (_) {}
  }

  // === Seleziona PRE ===
  Future<void> _pickPreImage() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) return;

    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty) return;
    final media = await paths.first.getAssetListPaged(page: 0, size: 100);
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
        preAngle = 0.0; // placeholder, in reale da sensore
        preDistance = 30.0; // placeholder, in reale da distanza overlay
      });
    }
  }

  // === Scatta POST ===
  Future<void> _capturePostImage() async {
    if (preFile == null) return;
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    final result = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraOverlayPage(
          cameras: cameras,
          initialCamera: firstCamera,
          guideImage: preImage!,
          preAngle: preAngle,
          preDistance: preDistance,
        ),
      ),
    );
    if (result != null) {
      final analyzed = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisPreview(
            imagePath: result.path,
            mode: "prepost",
          ),
        ),
      );
      if (analyzed != null) {
        final overlayPath = analyzed["overlay_path"] as String?;
        final newPostFile = analyzed["filename"] as String?;
        if (overlayPath != null) {
          setState(() => postImage = File(overlayPath));
        }
        if (newPostFile != null) {
          setState(() => postFile = newPostFile);
          await _loadCompareResults();
        }
      }
    }
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
                ),
                child: preImage == null
                    ? const Center(child: Icon(Icons.add, size: 80, color: Colors.blue))
                    : Image.file(preImage!, fit: BoxFit.cover),
              ),
            ),
            GestureDetector(
              onTap: postImage == null ? _capturePostImage : null,
              child: Container(
                width: boxSize,
                height: boxSize,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: postImage == null
                    ? const Center(child: Icon(Icons.add, size: 80, color: Colors.green))
                    : Image.file(postImage!, fit: BoxFit.cover),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === CameraOverlayPage ===
class CameraOverlayPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final CameraDescription initialCamera;
  final File guideImage;
  final double? preAngle;
  final double? preDistance;

  const CameraOverlayPage({
    super.key,
    required this.cameras,
    required this.initialCamera,
    required this.guideImage,
    this.preAngle,
    this.preDistance,
  });

  @override
  State<CameraOverlayPage> createState() => _CameraOverlayPageState();
}

class _CameraOverlayPageState extends State<CameraOverlayPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  late CameraDescription currentCamera;
  bool _shooting = false;

  // === variabili distanza ===
  double _lastIpdPx = 0.0;
  double _ipdMm = 63.0;
  final double _targetMmPerPx = 0.117;

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
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _takePicture() async {
    if (_shooting) return;
    setState(() => _shooting = true);
    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      Navigator.pop(context, File(image.path));
    } catch (_) {} finally {
      setState(() => _shooting = false);
    }
  }

  Widget _buildOverlay(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final double squareSize = min(300, screenW * 0.8);
    final bool isFront =
        currentCamera.lensDirection == CameraLensDirection.front;

    return Stack(
      children: [
        Align(
          alignment: const Alignment(0, -0.3),
          child: Container(
            width: squareSize,
            height: squareSize,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.yellow, width: 4),
            ),
          ),
        ),
        // Livella verticale attuale
        buildLivellaVerticaleOverlay(),
        // Distanza cm attuale
        buildDistanzaCmOverlay(
          ipdPx: _lastIpdPx,
          ipdMm: _ipdMm,
          targetMmPerPx: _targetMmPerPx,
          alignY: 0.8,
          isFrontCamera: isFront,
          mode: CaptureMode.volto,
        ),
        // Valori PRE
        if (widget.preAngle != null && widget.preDistance != null)
          Positioned(
            top: 40,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("PRE: ${widget.preAngle!.toStringAsFixed(1)}°",
                    style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text("PRE: ${widget.preDistance!.toStringAsFixed(1)} cm",
                    style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done &&
              _controller != null) {
            return Stack(
              children: [
                CameraPreview(_controller!),
                _buildOverlay(context),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: IconButton(
                    icon: const Icon(Icons.camera, color: Colors.white, size: 48),
                    onPressed: _takePicture,
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

// === Livella verticale con gradi ===
Widget buildLivellaVerticaleOverlay({
  double okThresholdDeg = 1.0,
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
              angleDeg = (acos(c) * 180.0 / pi);
            }
          }
          final bool isOk = (angleDeg - 90.0).abs() <= okThresholdDeg;
          final Color bigColor = isOk ? Colors.greenAccent : Colors.white;
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
