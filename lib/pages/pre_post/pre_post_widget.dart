import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:flutter/rendering.dart';

// importa AnalysisPreview per analisi sul server
import '../analysis_preview.dart';
// importa la camera POST (solo UI + scatto)
import '../post_camera_widget.dart';

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

  // per esportare foto+barre
  final GlobalKey _exportKey = GlobalKey();

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
      });

      // 🔹 Usa timestamp per cercare nel DB il filename corretto
final ts = file.lastModifiedSync().millisecondsSinceEpoch;

try {
  final url = Uri.parse("http://46.101.223.88:5000/find_by_timestamp?ts=$ts");
  final resp = await http.get(url);

  if (resp.statusCode == 200) {
    final data = jsonDecode(resp.body);
    final serverFilename = data["filename"];

    if (serverFilename != null && serverFilename.toString().contains("photo_")) {
      // ✅ Usa il nome reale del DB (es. photo_1759751234567.jpg)
      setState(() {
        preFile = serverFilename;
        preImage = file;
      });
      debugPrint("✅ PRE associato al record DB: $serverFilename");
    } else {
      // ⚠️ Nessun match nel DB, fallback su nome locale
      setState(() {
        preFile = path.basename(file.path);
        preImage = file;
      });
      debugPrint("⚠️ Nessun match nel DB, uso nome locale: ${path.basename(file.path)}");
    }
  } else {
    // ⚠️ Server non ha risposto correttamente → fallback
    setState(() {
      preFile = path.basename(file.path);
      preImage = file;
    });
    debugPrint("⚠️ Server non ha risposto, uso nome locale: ${path.basename(file.path)}");
  }
} catch (e) {
  debugPrint("❌ Errore lookup PRE: $e");
  setState(() {
    preFile = path.basename(file.path);
    preImage = file;
  });
}
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

    final result = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) => PostCameraWidget(
          guideImage: preImage, // 👈 overlay PRE
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

  // === Conferma rifai POST ===
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

  // === Esporta e salva in Galleria ===
  Future<void> _exportAndSaveToGallery() async {
    try {
      RenderRepaintBoundary boundary =
          _exportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) throw Exception("Decode fallita");
      final jpegBytes = img.encodeJpg(decoded, quality: 90);

      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permesso galleria negato")),
        );
        return;
      }

      final filename = "prepost_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final asset = await PhotoManager.editor.saveImage(
        Uint8List.fromList(jpegBytes),
        filename: filename,
      );

      if (asset != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Esportato e salvato in Galleria")),
        );
      } else {
        throw Exception("Salvataggio fallito");
      }
    } catch (e) {
      debugPrint("❌ Errore export: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore export: $e")),
      );
    }
  }

  // === Fullscreen singola immagine ===
  void _showFullscreenImage(File image) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          child: Center(child: Image.file(image, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  // === Fullscreen swipe PRE/POST ===
  void _showSwipeViewer(File pre, File post) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: PageView(
            children: [
              InteractiveViewer(
                child: Center(child: Image.file(pre, fit: BoxFit.contain)),
              ),
              InteractiveViewer(
                child: Center(child: Image.file(post, fit: BoxFit.contain)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double boxSize = MediaQuery.of(context).size.width / 2;

    return Scaffold(
      appBar: AppBar(title: const Text("Pre/Post")),
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: _exportKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (preImage != null && postImage != null) {
                          _showSwipeViewer(preImage!, postImage!);
                        } else if (preImage != null) {
                          _showFullscreenImage(preImage!);
                        } else {
                          _pickPreImage();
                        }
                      },
                      child: Container(
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
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (preImage != null && postImage != null) {
                          _showSwipeViewer(preImage!, postImage!);
                        } else if (postImage != null) {
                          _showFullscreenImage(postImage!);
                        } else {
                          _capturePostImage();
                        }
                      },
                      onLongPress: postImage == null ? null : _confirmRetakePost,
                      child: Container(
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
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // === Risultati comparazione ===
              if (compareData != null) ...[
                // --- MACCHIE ---
                if (compareData!["macchie"] != null) _buildMacchieCard(),
                // --- PORI ---
                if (compareData!["pori"] != null) _buildPoriCard(),
                // --- RUGHE ---
                if (compareData!["rughe"] != null) _buildRugheCard(),
                // --- MELASMA ---
                if (compareData!["melasma"] != null) _buildMelasmaCard(),
              ]
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportAndSaveToGallery,
        icon: const Icon(Icons.download),
        label: const Text("Download"),
      ),
    );
  }

  // === CARDS COMPARAZIONE ===
  Widget _buildMacchieCard() {
  final macchie = compareData!["macchie"];

  final double percPre = (macchie["percentuale_pre"] ?? 0.0).toDouble();
  final double percPost = (macchie["percentuale_post"] ?? 0.0).toDouble();
  final double percDiff = (macchie["percentuale_diff"] ?? 0.0).toDouble();

  final int numPre = (macchie["numero_pre"] ?? 0).toInt();
  final int numPost = (macchie["numero_post"] ?? 0).toInt();
  final int numComuni = (macchie["numero_comuni"] ?? 0).toInt();
  final double diffAbs = (macchie["differenza_assoluta"] ?? 0).toDouble();
  final double diffPerc = (macchie["differenza_percentuale"] ?? 0).toDouble();

  return Card(
    margin: const EdgeInsets.all(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📊 Comparazione Macchie",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          _buildBar("Percentuale PRE", percPre, Colors.green),
          _buildBar("Percentuale POST", percPost, Colors.blue),

          _buildBar(
            "Differenza % Area",
            percDiff.abs(),
            percDiff <= 0 ? Colors.green : Colors.red,
          ),

          const SizedBox(height: 12),
          Text("Numero macchie PRE: $numPre"),
          Text("Numero macchie POST: $numPost"),
          Text("Macchie comuni: $numComuni"),
          Text("Differenza assoluta: ${diffAbs.toStringAsFixed(0)}"),
          Text("Differenza % numero: ${diffPerc.toStringAsFixed(2)}%"),
        ],
      ),
    ),
  );
}


  Widget _buildPoriCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("📊 Area Pori dilatati (rossi)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            _buildBar("Area Pre",
                compareData!["pori"]["perc_pre_dilatati"] ?? 0.0, Colors.green),
            Text(
                "Normali: ${compareData!["pori"]["num_pori_pre"]["normali"]}, Borderline: ${compareData!["pori"]["num_pori_pre"]["borderline"]}, Dilatati: ${compareData!["pori"]["num_pori_pre"]["dilatati"]}, Totali: ${compareData!["pori"]["num_pori_pre"]["totali"]}"),
            _buildBar("Area Post",
                compareData!["pori"]["perc_post_dilatati"] ?? 0.0, Colors.blue),
            Text(
                "Normali: ${compareData!["pori"]["num_pori_post"]["normali"]}, Borderline: ${compareData!["pori"]["num_pori_post"]["borderline"]}, Dilatati: ${compareData!["pori"]["num_pori_post"]["dilatati"]}, Totali: ${compareData!["pori"]["num_pori_post"]["totali"]}"),
            Builder(
              builder: (_) {
                final double pre =
                    (compareData!["pori"]["perc_pre_dilatati"] ?? 0.0)
                        .toDouble();
                final double post =
                    (compareData!["pori"]["perc_post_dilatati"] ?? 0.0)
                        .toDouble();
                double diffPerc = 0.0;
                if (pre > 0) diffPerc = ((post - pre) / pre) * 100;
                return _buildBar("Differenza Area", diffPerc.abs(),
                    diffPerc <= 0 ? Colors.green : Colors.red);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRugheCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("📊 Area Rughe",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            _buildBar("Area Pre", compareData!["rughe"]["perc_pre"] ?? 0.0,
                Colors.green),
            _buildBar("Area Post", compareData!["rughe"]["perc_post"] ?? 0.0,
                Colors.blue),
            Builder(
              builder: (_) {
                final double pre =
                    (compareData!["rughe"]["perc_pre"] ?? 0.0).toDouble();
                final double post =
                    (compareData!["rughe"]["perc_post"] ?? 0.0).toDouble();
                double diffPerc = 0.0;
                if (pre > 0) {
                  diffPerc = ((post - pre) / pre) * 100;
                  diffPerc -= 5;
                }
                return _buildBar("Differenza Area", diffPerc.abs(),
                    diffPerc <= 0 ? Colors.green : Colors.red);
              },
            ),
            Text(
                "Area PRE: ${(compareData!["rughe"]["area_pre"] ?? 0).toStringAsFixed(2)} cm²"),
            Text(
                "Area POST: ${(compareData!["rughe"]["area_post"] ?? 0).toStringAsFixed(2)} cm²"),
            Text(
                "Diff area: ${(compareData!["rughe"]["area_diff"] ?? 0).toStringAsFixed(2)} cm²"),
          ],
        ),
      ),
    );
  }

  Widget _buildMelasmaCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("📊 Area Melasma",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            _buildBar("Area Pre",
                compareData!["melasma"]["perc_pre"] ?? 0.0, Colors.green),
            _buildBar("Area Post",
                compareData!["melasma"]["perc_post"] ?? 0.0, Colors.blue),
            Builder(
              builder: (_) {
                final double pre =
                    (compareData!["melasma"]["perc_pre"] ?? 0.0).toDouble();
                final double post =
                    (compareData!["melasma"]["perc_post"] ?? 0.0).toDouble();
                double diffPerc = 0.0;
                if (pre > 0) diffPerc = ((post - pre) / pre) * 100;
                return _buildBar("Differenza Area", diffPerc.abs(),
                    diffPerc <= 0 ? Colors.green : Colors.red);
              },
            ),
            Text(
                "Area PRE: ${(compareData!["melasma"]["area_pre"] ?? 0).toStringAsFixed(2)} cm²"),
            Text(
                "Area POST: ${(compareData!["melasma"]["area_post"] ?? 0).toStringAsFixed(2)} cm²"),
            Text(
                "Diff area: ${(compareData!["melasma"]["area_diff"] ?? 0).toStringAsFixed(2)} cm²"),
          ],
        ),
      ),
    );
  }
}
