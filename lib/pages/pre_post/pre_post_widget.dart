import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';

class PrePostWidget extends StatefulWidget {
  const PrePostWidget({super.key});

  @override
  State<PrePostWidget> createState() => _PrePostWidgetState();
}

class _PrePostWidgetState extends State<PrePostWidget> {
  File? preImage;
  File? postImage;
  double? prePercent;
  double? postPercent;

  // === Carica PRE dalla galleria con photo_manager ===
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
        await paths.first.getAssetListPaged(page: 0, size: 60);
    if (media.isEmpty) return;

    final File? file = await media.first.file;
    if (file != null) {
      setState(() {
        preImage = file;
        prePercent = _fakeAnalysis();
      });
    }
  }

  // === Scatta POST con camera (overlay guida pre) ===
  Future<void> _capturePostImage() async {
    if (preImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Carica prima la foto PRE dalla galleria")),
      );
      return;
    }

    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    final result = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CameraOverlayPage(camera: firstCamera, guideImage: preImage!),
      ),
    );

    if (result != null) {
      setState(() {
        postImage = result;
        postPercent = _fakeAnalysis();
      });
    }
  }

  // === funzione analisi simulata ===
  double _fakeAnalysis() {
    return 20 + Random().nextInt(50).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    double? diff;
    if (prePercent != null && postPercent != null) {
      diff = postPercent! - prePercent!;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Pre/Post")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // BOX PRE
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickPreImage,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blueAccent, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: preImage == null
                            ? const Center(
                                child: Icon(Icons.add,
                                    size: 60, color: Colors.blue),
                              )
                            : Image.file(preImage!, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  // BOX POST
                  Expanded(
                    child: GestureDetector(
                      onTap: _capturePostImage,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: postImage == null
                            ? const Center(
                                child: Icon(Icons.add,
                                    size: 60, color: Colors.green),
                              )
                            : Image.file(postImage!, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (prePercent != null || postPercent != null)
              Column(
                children: [
                  if (prePercent != null)
                    Text("Pre: ${prePercent!.toStringAsFixed(1)}%",
                        style: const TextStyle(fontSize: 16)),
                  if (postPercent != null)
                    Text("Post: ${postPercent!.toStringAsFixed(1)}%",
                        style: const TextStyle(fontSize: 16)),
                  if (diff != null)
                    Text(
                      "Differenza: ${diff.toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: diff > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// === Pagina Camera con overlay guida ===
class CameraOverlayPage extends StatefulWidget {
  final CameraDescription camera;
  final File guideImage;

  const CameraOverlayPage(
      {super.key, required this.camera, required this.guideImage});

  @override
  State<CameraOverlayPage> createState() => _CameraOverlayPageState();
}

class _CameraOverlayPageState extends State<CameraOverlayPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _initializeControllerFuture = _controller!.initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      Navigator.pop(context, File(image.path));
    } catch (e) {
      debugPrint("Errore scatto: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scatta Foto Post")),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller!),
                // Overlay guida (foto pre semitrasparente)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.4,
                    child: Image.file(widget.guideImage, fit: BoxFit.cover),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: FloatingActionButton(
                      onPressed: _takePicture,
                      child: const Icon(Icons.camera_alt),
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
