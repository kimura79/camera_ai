import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:custom_camera_component/pages/analysis_preview.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http; // 🔹 per cancellare job lato server
import 'dart:convert';

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
  String? activeJobId; // 🔹 job corrente sul server

  // === API server base URL ===
  final String serverUrl = "http://46.101.223.88:5000";

  // === Seleziona PRE dalla galleria ===
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
    builder: (context) => HomePageWidget(), // 👈 togli const
  ),
);

    if (result != null) {
  // 🔹 Apri la pagina di analisi e attendi il file elaborato (overlay)
  final analyzed = await Navigator.push<File?>(
    context,
    MaterialPageRoute(
      builder: (context) => AnalysisPreview(
        imagePath: result.path,
        mode: "fullface", // o "particolare" a seconda del caso
      ),
      settings: const RouteSettings(arguments: "prepost"), // 🔹 segnala che siamo in PrePost
    ),
  );

  // Se AnalysisPreview restituisce un file overlay, lo usiamo come Post
  if (analyzed != null) {
    setState(() {
      postImage = analyzed;
      postPercent = _fakeAnalysis();
    });
  } else {
    // fallback: se non arriva overlay, usiamo comunque la foto grezza
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

  // === Cancella job e resetta tutto ===
  Future<void> _cancelAndReset() async {
    if (activeJobId != null) {
      try {
        await http.post(Uri.parse("$serverUrl/cancel_job/$activeJobId"));
      } catch (e) {
        debugPrint("Errore cancellazione job: $e");
      }
    }
    setState(() {
      preImage = null;
      postImage = null;
      prePercent = null;
      postPercent = null;
      activeJobId = null;
    });
  }

  // === Crea immagine affiancata e salva in galleria ===
  Future<void> _saveComparisonImage() async {
    if (preImage == null || postImage == null) return;

    final preBytes = await preImage!.readAsBytes();
    final postBytes = await postImage!.readAsBytes();
    final pre = img.decodeImage(preBytes);
    final post = img.decodeImage(postBytes);

    if (pre == null || post == null) return;

    final resizedPre = img.copyResize(pre, width: 1024, height: 1024);
    final resizedPost = img.copyResize(post, width: 1024, height: 1024);

    final combined = img.Image(
      width: resizedPre.width * 2,
      height: resizedPre.height,
    );

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
    double? diff;
    if (prePercent != null && postPercent != null) {
      diff = postPercent! - prePercent!;
    }

    final double boxSize = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        // 🔹 se job attivo → cancella tutto
        if (activeJobId != null) {
          await _cancelAndReset();
        }
        return true; // consenti back
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
                          child: Icon(Icons.add, size: 80, color: Colors.blue),
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
                      Column(
                        children: [
                          Text("Pre: ${prePercent!.toStringAsFixed(1)}%",
                              style: const TextStyle(fontSize: 16)),
                          LinearProgressIndicator(
                            value: prePercent! / 100,
                            backgroundColor: Colors.grey[300],
                            color: Colors.blueAccent,
                            minHeight: 12,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    if (postPercent != null)
                      Column(
                        children: [
                          Text("Post: ${postPercent!.toStringAsFixed(1)}%",
                              style: const TextStyle(fontSize: 16)),
                          LinearProgressIndicator(
                            value: postPercent! / 100,
                            backgroundColor: Colors.grey[300],
                            color: Colors.green,
                            minHeight: 12,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    if (diff != null)
                      Text(
                        "Differenza: ${diff.toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontSize: 18,
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
                    const SizedBox(height: 20),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
