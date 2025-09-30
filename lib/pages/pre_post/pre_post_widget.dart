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
    debugPrint("🔵 initState → preFile=$preFile postFile=$postFile");
    if (preFile != null && postFile != null) {
      _loadCompareResults();
    }
  }

  // === Carica risultati comparazione dal server ===
  Future<void> _loadCompareResults() async {
    if (preFile == null || postFile == null) {
      debugPrint("⚠️ _loadCompareResults → preFile=$preFile postFile=$postFile → skip");
      return;
    }

    final url = Uri.parse(
        "http://46.101.223.88:5000/compare_from_db?pre_file=$preFile&post_file=$postFile");
    debugPrint("🌍 Chiamata GET compare_from_db: $url");

    try {
      final resp = await http.get(url);
      debugPrint("📡 Response code: ${resp.statusCode}");
      debugPrint("📡 Response body: ${resp.body}");

      if (resp.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(resp.body);
        if (data.isEmpty) {
          debugPrint("⚠️ JSON vuoto → nessun dato di comparazione");
        } else {
          setState(() => compareData = data);
          debugPrint("✅ compareData popolato: $compareData");
        }
      } else {
        debugPrint("❌ Errore server compare_from_db: ${resp.body}");
      }
    } catch (e) {
      debugPrint("❌ Errore richiesta compare_from_db: $e");
    }
  }

  // === Seleziona PRE dalla galleria ===
  Future<void> _pickPreImage() async {
    debugPrint("📂 Avvio selezione PRE da galleria");
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      debugPrint("❌ Permesso galleria negato");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permesso galleria negato")),
      );
      return;
    }

    final List<AssetPathEntity> paths =
        await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty) {
      debugPrint("⚠️ Nessuna cartella immagini trovata");
      return;
    }

    final List<AssetEntity> media =
        await paths.first.getAssetListPaged(page: 0, size: 100);
    if (media.isEmpty) {
      debugPrint("⚠️ Nessuna immagine in galleria");
      return;
    }

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
                        debugPrint("📷 PRE selezionato: ${f?.path}");
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

      final ts = file.lastModifiedSync().millisecondsSinceEpoch;
      debugPrint("🔍 Lookup PRE in DB con timestamp=$ts");

      try {
        final url =
            Uri.parse("http://46.101.223.88:5000/find_by_timestamp?ts=$ts");
        final resp = await http.get(url);
        debugPrint("📡 find_by_timestamp code=${resp.statusCode} body=${resp.body}");

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final serverFilename = data["filename"];
          if (serverFilename != null) {
            setState(() {
              preFile = serverFilename;
            });
            debugPrint("✅ PRE associato a DB: $serverFilename");
          } else {
            setState(() {
              preFile = path.basename(file.path);
            });
            debugPrint("⚠️ Nessun match DB, uso filename locale=$preFile");
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

  // === Scatta POST ===
  Future<void> _capturePostImage() async {
    if (preFile == null) {
      debugPrint("⚠️ Non hai selezionato PRE prima del POST");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Devi avere un PRE prima del POST")),
      );
      return;
    }

    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    debugPrint("📸 Avvio fotocamera POST...");

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
      debugPrint("📸 Foto POST acquisita: ${result.path}");

      final analyzed = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisPreview(
            imagePath: result.path,
            mode: "prepost",
          ),
        ),
      );

      debugPrint("🟢 Ritorno da AnalysisPreview: $analyzed");

      if (analyzed != null) {
        final overlayPath = analyzed["overlay_path"] as String?;
        final newPostFile = analyzed["filename"] as String?;

        debugPrint("📂 overlayPath=$overlayPath newPostFile=$newPostFile");

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
          debugPrint("✅ POST associato a DB: $newPostFile");
          await _loadCompareResults();
        }
      }
    }
  }

  // === Widget barra percentuale ===
  Widget _buildBar(String label, double value, Color color) {
    debugPrint("📊 Build bar $label → ${value.toStringAsFixed(2)}%");
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

    debugPrint("🔄 build() → compareData=$compareData");

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
              onTap: postImage == null ? _capturePostImage : null,
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
            if (compareData == null)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "⚠️ Nessun dato di comparazione trovato.\n"
                  "Controlla i log debugPrint per capire cosa non arriva.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              )
            else ...[
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
                            Colors.green),
                        _buildBar(
                            "Post",
                            (compareData!["macchie"]["perc_post"] ?? 0.0)
                                .toDouble(),
                            Colors.blue),
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
                            (compareData!["pori"]["perc_pre_dilatati"] ?? 0.0)
                                .toDouble(),
                            Colors.green),
                        _buildBar(
                            "Post",
                            (compareData!["pori"]["perc_post_dilatati"] ?? 0.0)
                                .toDouble(),
                            Colors.blue),
                        _buildBar(
                            "Differenza",
                            (compareData!["pori"]["perc_diff_dilatati"] ?? 0.0)
                                .abs()
                                .toDouble(),
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
