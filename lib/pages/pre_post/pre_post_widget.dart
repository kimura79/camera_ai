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

enum CaptureMode { volto, particolare }

// === Overlay distanza cm (uguale alla fotocamera PRE) ===
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,
  double alignY = 0.0,
  CaptureMode mode = CaptureMode.volto,
}) {
  String testo;
  Color borderColor = Colors.yellow;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    final mmPerPxAttuale = ipdMm / ipdPx;
    final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
    if (distCm > 5 && distCm < 100) {
      testo = '${distCm.toStringAsFixed(1)} cm';
    } else {
      testo = '— cm';
    }
    borderColor = ((distCm - 30).abs() < 2) ? Colors.green : Colors.yellow;
  }

  return Align(
    alignment: Alignment.center,
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
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class PrePostWidget extends StatefulWidget {
  final String? preFile;
  final String? postFile;

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
        preAngle = 0.0;
        preDistance = 30.0;
      });
    }
  }

  // === Scatta POST ===
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
          setState(() {
            postImage = File(overlayPath);
          });
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
              onTap: postImage == null ? _capturePostImage : _confirmRetakePost,
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

// === CameraOverlayPage (stile identico alla fotocamera PRE) ===
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

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    if (currentCamera.lensDirection == CameraLensDirection.front) {
      final back = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );
      currentCamera = back;
    } else {
      final front = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
      currentCamera = front;
    }
    await _initCamera();
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

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done &&
              _controller != null) {
            return Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),

                // Overlay PRE semitrasparente
                Center(
                  child: SizedBox(
                    width: min(1024, screenW),
                    height: min(1024, screenW),
                    child: Opacity(
                      opacity: 0.4,
                      child: Image.file(widget.guideImage, fit: BoxFit.cover),
                    ),
                  ),
                ),

                // Quadrato giallo 1:1
                Align(
                  alignment: const Alignment(0, -0.3),
                  child: Container(
                    width: min(300, screenW * 0.8),
                    height: min(300, screenW * 0.8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.yellow, width: 4),
                    ),
                  ),
                ),

                // Livella verticale
                buildLivellaVerticaleOverlay(),

                // Distanza cm attuale
                buildDistanzaCmOverlay(
                  ipdPx: _lastIpdPx,
                  ipdMm: _ipdMm,
                  targetMmPerPx: _targetMmPerPx,
                  alignY: 0.0,
                  isFrontCamera:
                      currentCamera.lensDirection == CameraLensDirection.front,
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

                // Pulsanti in basso
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 25),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black38,
                              ),
                              child: const Icon(Icons.image,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ),
                        GestureDetector(
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
                                    border: Border.all(
                                        color: Colors.white, width: 6),
                                  ),
                                ),
                                AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 80),
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
                        Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black38,
                              ),
                              child: const Icon(Icons.cameraswitch,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                      ],
                    ),
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

// === Livella verticale ===
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
