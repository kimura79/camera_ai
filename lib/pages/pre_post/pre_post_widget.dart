import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:custom_camera_component/pages/analysis_preview.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;

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
  String? activeJobId; // job corrente

  final String serverUrl = "http://46.101.223.88:5000";

  Future<void> _pickPreImage() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permesso galleria negato")),
      );
      return;
    }

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
                        final f = await media[index].file;
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

  Future<void> _capturePostImage() async {
    if (preImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Carica prima la foto PRE")),
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
      final analyzed = await Navigator.push<File?>(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisPreview(
            imagePath: result.path,
            mode: "fullface",
          ),
          settings: const RouteSettings(arguments: "prepost"),
        ),
      );

      if (analyzed != null) {
        setState(() {
          postImage = analyzed;
          postPercent = _fakeAnalysis();
        });
      } else {
        setState(() {
          postImage = result;
          postPercent = _fakeAnalysis();
        });
      }
    }
  }

  double _fakeAnalysis() {
    return 20 + Random().nextInt(50).toDouble();
  }

  Future<void> _cancelJobIfActive() async {
    if (activeJobId != null) {
      try {
        await http.post(Uri.parse("$serverUrl/cancel_job/$activeJobId"));
      } catch (_) {}
      setState(() => activeJobId = null);
    }
  }

  Future<void> _saveComparisonImage() async {
    if (preImage == null || postImage == null) return;
    final pre = img.decodeImage(await preImage!.readAsBytes());
    final post = img.decodeImage(await postImage!.readAsBytes());
    if (pre == null || post == null) return;

    final resizedPre = img.copyResize(pre, width: 1024, height: 1024);
    final resizedPost = img.copyResize(post, width: 1024, height: 1024);
    final combined = img.Image(resizedPre.width * 2, resizedPre.height);
    img.compositeImage(combined, resizedPre, dstX: 0, dstY: 0);
    img.compositeImage(combined, resizedPost, dstX: resizedPre.width, dstY: 0);
    final jpg = img.encodeJpg(combined, quality: 90);

    await PhotoManager.editor.saveImage(
      jpg,
      filename: "pre_post_${DateTime.now().millisecondsSinceEpoch}.jpg",
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Immagine salvata in galleria")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double? diff = (prePercent != null && postPercent != null)
        ? postPercent! - prePercent!
        : null;
    final boxSize = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        // se overlay non pronto → annulla job
        if (postImage == null) {
          await _cancelJobIfActive();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Pre/Post")),
        body: SingleChildScrollView(
          child: Column(
            children: [
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
                          child: Icon(Icons.add,
                              size: 80, color: Colors.blue),
                        )
                      : Image.file(preImage!, fit: BoxFit.cover),
                ),
              ),
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
                          child: Icon(Icons.add,
                              size: 80, color: Colors.green),
                        )
                      : Image.file(postImage!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 16),
              if (prePercent != null || postPercent != null)
                Column(
                  children: [
                    if (prePercent != null)
                      Column(
                        children: [
                          Text("Pre: ${prePercent!.toStringAsFixed(1)}%"),
                          LinearProgressIndicator(
                            value: prePercent! / 100,
                            backgroundColor: Colors.grey[300],
                            color: Colors.blueAccent,
                            minHeight: 12,
                          ),
                        ],
                      ),
                    if (postPercent != null)
                      Column(
                        children: [
                          Text("Post: ${postPercent!.toStringAsFixed(1)}%"),
                          LinearProgressIndicator(
                            value: postPercent! / 100,
                            backgroundColor: Colors.grey[300],
                            color: Colors.green,
                            minHeight: 12,
                          ),
                        ],
                      ),
                    if (diff != null)
                      Text(
                        "Differenza: ${diff.toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: diff > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _saveComparisonImage,
                      icon: const Icon(Icons.download),
                      label: const Text("Scarica confronto"),
                    ),
                  ],
                ),
            ],
          ),
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
      currentCamera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );
    } else {
      currentCamera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
    }
    await _initCamera();
  }

  Future<void> _takePicture() async {
    try {
      if (_shooting) return;
      setState(() => _shooting = true);
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      File file = File(image.path);

      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded != null) {
        final side = min(decoded.width, decoded.height);
        final x = (decoded.width - side) ~/ 2;
        final y = (decoded.height - side) ~/ 2;
        var cropped = img.copyCrop(decoded, x: x, y: y, width: side, height: side);
        cropped = img.copyResize(cropped, width: 1024, height: 1024);
        if (currentCamera.lensDirection == CameraLensDirection.front) {
          cropped = img.flipHorizontal(cropped);
        }
        file = await File("${file.path}_square.jpg")
            .writeAsBytes(img.encodeJpg(cropped));
      }
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      debugPrint("Errore scatto: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close,
                              size: 36, color: Colors.white),
                        ),
                        GestureDetector(
                          onTap: _takePicture,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _switchCamera,
                          child: const Icon(Icons.cameraswitch,
                              size: 36, color: Colors.white),
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
