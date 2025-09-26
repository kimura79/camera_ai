import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// importa AnalysisPreview per analisi sul server
import '../analysis_preview.dart';

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

  // === Seleziona PRE dalla galleria (SOLO CARICAMENTO, NO ANALISI) ===
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
        preFile = file.uri.pathSegments.last; // ⬅️ usa filename univoco
      });
      debugPrint("✅ Foto PRE caricata: ${file.path}");
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
            mode: "prepost",   // il server userà prefix POST_
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

  Widget _buildBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ${value.toStringAsFixed(2)}%"),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value / 100,
          backgroundColor: Colors.grey[300],
          color: color,
          minHeight: 10,
        ),
        const SizedBox(height: 12),
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
              if (compareData!.containsKey("macchie")) ...[
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
                        _buildBar("Pre", compareData!["macchie"]["perc_pre"], Colors.green),
                        _buildBar("Post", compareData!["macchie"]["perc_post"], Colors.blue),
                        Text(
                          "Differenza: ${compareData!["macchie"]["perc_diff"].toStringAsFixed(2)}%",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (compareData!.containsKey("pori")) ...[
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("📊 Percentuali Pori dilatati (rossi)",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        _buildBar("Pre", compareData!["pori"]["perc_pre_dilatati"], Colors.orange),
                        _buildBar("Post", compareData!["pori"]["perc_post_dilatati"], Colors.red),
                        Text(
                          "Differenza: ${compareData!["pori"]["perc_diff_dilatati"].toStringAsFixed(2)}%",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ]
          ],
        ),
      ),
    );
  }
}

// === Camera con overlay guida ===
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
    _initializeControllerFuture = _controller!.initialize().then((_) async {
      await _controller!.setFlashMode(FlashMode.off);
    });
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

  @override
  void dispose() {
    _controller?.dispose();
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

        cropped = img.copyResize(cropped, width: 1024, height: 1024);

        if (currentCamera.lensDirection == CameraLensDirection.front) {
          cropped = img.flipHorizontal(cropped);
        }

        final outPath = "${file.path}_square.jpg";
        file = await File(outPath).writeAsBytes(img.encodeJpg(cropped));
      }

      Navigator.pop(context, file);
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller != null) {
            return Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),
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
