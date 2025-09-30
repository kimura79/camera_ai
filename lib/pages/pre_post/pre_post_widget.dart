import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

// importa AnalysisPreview per analisi sul server
import '../analysis_preview.dart';
// importa la fotocamera dedicata al POST
import '../post_camera_widget.dart';

class PrePostWidget extends StatefulWidget {
  final String? preFile; // Filename analisi PRE nel DB
  final String? postFile; // Filename analisi POST nel DB

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

  /// 🔹 Utility per ripulire il nome file da prefissi tipo "PRE_overlay_macchie_..."
  String _normalizeFilename(String fileName) {
    // Se contiene "photo_", prendi tutto da lì in poi
    final idx = fileName.indexOf("photo_");
    if (idx != -1) {
      return fileName.substring(idx);
    }
    // Altrimenti lascia invariato
    return fileName;
  }

  // === Carica risultati comparazione dal server ===
  Future<void> _loadCompareResults() async {
    if (preFile == null || postFile == null) {
      debugPrint("⚠️ preFile o postFile mancanti, skip comparazione");
      return;
    }

    // 🔹 Normalizza i nomi prima di passarli al server
    final cleanPre = _normalizeFilename(preFile!);
    final cleanPost = _normalizeFilename(postFile!);

    final url = Uri.parse(
        "http://46.101.223.88:5000/compare_from_db?pre_file=$cleanPre&post_file=$cleanPost");
    try {
      final resp = await http.get(url);
      debugPrint("📡 Risposta server (${resp.statusCode}): ${resp.body}");

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);

        // 🔹 Normalizzazione dei dati per compatibilità UI
        setState(() {
          compareData = {
            "macchie": decoded["macchie"] != null
                ? {
                    "perc_pre": decoded["macchie"]["perc_pre"] ?? 0.0,
                    "perc_post": decoded["macchie"]["perc_post"] ?? 0.0,
                    "numero_macchie_pre":
                        decoded["macchie"]["numero_macchie_pre"] ?? 0,
                    "numero_macchie_post":
                        decoded["macchie"]["numero_macchie_post"] ?? 0,
                  }
                : null,
            "pori": decoded["pori"] != null
                ? {
                    "perc_pre_dilatati":
                        decoded["pori"]["perc_pre_dilatati"] ?? 0.0,
                    "perc_post_dilatati":
                        decoded["pori"]["perc_post_dilatati"] ?? 0.0,
                    "num_pori_pre": decoded["pori"]["num_pori_pre"] ?? {
                      "normali": 0,
                      "borderline": 0,
                      "dilatati": 0,
                    },
                    "num_pori_post": decoded["pori"]["num_pori_post"] ?? {
                      "normali": 0,
                      "borderline": 0,
                      "dilatati": 0,
                    },
                  }
                : null,
          };
        });

        debugPrint("✅ Dati comparazione normalizzati: $compareData");
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
        preFile = path.basename(file.path);
      });
    }
  }

  // === Scatta POST ===
  Future<void> _capturePostImage() async {
    if (preImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Devi avere un PRE prima del POST")),
      );
      return;
    }

    final analyzed = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (context) => PostCameraWidget(
          guideImage: preImage, // 👈 overlay della foto PRE
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

  // === Conferma rifare POST ===
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

  // === Calcolo colore differenza ===
  Color _diffColor(double pre, double post) {
    if (post < pre) {
      return Colors.green; // miglioramento
    } else if (post > pre) {
      return Colors.red; // peggioramento
    } else {
      return Colors.grey; // invariato
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
            // Box PRE
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
            // Box POST
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
              // --- Macchie
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
                          (compareData!["macchie"]["perc_pre"] ?? 0.0)
                              .toDouble(),
                          Colors.green,
                        ),
                        _buildBar(
                          "Post",
                          (compareData!["macchie"]["perc_post"] ?? 0.0)
                              .toDouble(),
                          Colors.blue,
                        ),
                        Builder(
                          builder: (_) {
                            final pre =
                                (compareData!["macchie"]["perc_pre"] ?? 0.0)
                                    .toDouble();
                            final post =
                                (compareData!["macchie"]["perc_post"] ?? 0.0)
                                    .toDouble();
                            final diff = post - pre;
                            return _buildBar(
                              "Differenza",
                              diff,
                              _diffColor(pre, post),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                            "Numero PRE: ${compareData!["macchie"]["numero_macchie_pre"] ?? '-'}"),
                        Text(
                            "Numero POST: ${compareData!["macchie"]["numero_macchie_post"] ?? '-'}"),
                      ],
                    ),
                  ),
                ),

              // --- Pori
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
                          (compareData!["pori"]["perc_pre_dilatati"] ?? 0.0)
                              .toDouble(),
                          Colors.green,
                        ),
                        _buildBar(
                          "Post",
                          (compareData!["pori"]["perc_post_dilatati"] ?? 0.0)
                              .toDouble(),
                          Colors.blue,
                        ),
                        Builder(
                          builder: (_) {
                            final pre =
                                (compareData!["pori"]["perc_pre_dilatati"] ??
                                        0.0)
                                    .toDouble();
                            final post =
                                (compareData!["pori"]["perc_post_dilatati"] ??
                                        0.0)
                                    .toDouble();
                            final diff = post - pre;
                            return _buildBar(
                              "Differenza",
                              diff,
                              _diffColor(pre, post),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                            "PRE → Normali: ${compareData!["pori"]["num_pori_pre"]["normali"] ?? '-'}, "
                            "Borderline: ${compareData!["pori"]["num_pori_pre"]["borderline"] ?? '-'}, "
                            "Dilatati: ${compareData!["pori"]["num_pori_pre"]["dilatati"] ?? '-'}"),
                        Text(
                            "POST → Normali: ${compareData!["pori"]["num_pori_post"]["normali"] ?? '-'}, "
                            "Borderline: ${compareData!["pori"]["num_pori_post"]["borderline"] ?? '-'}, "
                            "Dilatati: ${compareData!["pori"]["num_pori_post"]["dilatati"] ?? '-'}"),
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
