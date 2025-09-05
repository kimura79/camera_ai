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

  // === Seleziona PRE dalla galleria ===
  Future<void> _pickPreImage() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permesso galleria negato")),
      );
      return;
    }

    // prendo tutte le immagini della galleria
    final List<AssetPathEntity> paths =
        await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty) return;

    final List<AssetEntity> media =
        await paths.first.getAssetListPaged(page: 0, size: 100);
    if (media.isEmpty) return;

    // mostro la lista in un semplice dialog di selezione
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
                future: media[index].thumbnailDataWithSize(const ThumbnailSize(200, 200)),
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
        prePercent = _fakeAnalysis();
      });
    }
  }

  // === Scatta POST con camera ===
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
        builder: (context) => CameraOverlayPage(
          cameras: cameras,
          initialCamera: firstCamera,
          guideImage: preImage!,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        postImage = result;
        postPercent = _fakeAnalysis();
      });
    }
  }

  double _fakeAnalysis() {
    return 20 + Random().nextInt(50).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    double? diff;
    if (prePercent != null && postPercent != null) {
      diff = postPercent! - prePercent!;
    }

    final double boxSize = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(title: const Text("Pre/Post")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // BOX PRE (sopra)
            GestureDetector(
              onTap: _pickPreImage,
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

            // BOX POST (sotto)
            GestureDetector(
              onTap: _capturePostImage,
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

// === Camera con overlay guida centrata 1024x1024 + switch camera ===
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

  @override
  void initState() {
    super.initState();
    currentCamera = widget.initialCamera;
    _initCamera();
  }

  void _initCamera() {
    _controller = CameraController(currentCamera, ResolutionPreset.high);
    _initializeControllerFuture = _controller!.initialize();
    setState(() {});
  }

  void _switchCamera() {
    if (widget.cameras.length < 2) return;
    currentCamera = (currentCamera == widget.cameras.first)
        ? widget.cameras.last
        : widget.cameras.first;
    _initCamera();
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
    final double screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(title: const Text("Scatta Foto Post")),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller != null) {
            return Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),

                // Overlay guida centrata 1024x1024
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

                // Pulsanti scatto e switch
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FloatingActionButton(
                          heroTag: "switch",
                          onPressed: _switchCamera,
                          child: const Icon(Icons.cameraswitch),
                        ),
                        FloatingActionButton(
                          heroTag: "capture",
                          onPressed: _takePicture,
                          child: const Icon(Icons.camera_alt),
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
