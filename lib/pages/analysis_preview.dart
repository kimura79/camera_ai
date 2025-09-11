import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart'; // per compute JSON
import 'package:custom_camera_component/services/api_service.dart';

class AnalysisPreview extends StatefulWidget {
  final String imagePath;
  final String mode; // "fullface" o "particolare"

  const AnalysisPreview({
    super.key,
    required this.imagePath,
    this.mode = "fullface",
  });

  @override
  State<AnalysisPreview> createState() => _AnalysisPreviewState();
}

class _AnalysisPreviewState extends State<AnalysisPreview> {
  bool _loading = false;

  Map<String, dynamic>? _rugheResult;
  String? _rugheOverlayUrl;
  double? _rughePercentuale;

  Map<String, dynamic>? _macchieResult;
  String? _macchieOverlayUrl;
  double? _macchiePercentuale;

  Map<String, dynamic>? _melasmaResult;
  String? _melasmaOverlayUrl;
  double? _melasmaPercentuale;

  // === Salvataggio overlay sul main isolate ===
  Future<void> _saveOverlayOnMain({
    required String url,
    required String tipo,
  }) async {
    try {
      final overlayResp = await http.get(Uri.parse(url));
      if (overlayResp.statusCode != 200) return;

      final bytes = overlayResp.bodyBytes;

      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      final bool granted = pState.isAuth || pState.hasAccess;
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Permesso galleria negato")),
        );
        return;
      }

      final asset = await PhotoManager.editor.saveImage(
				  bytes,
				  filename: "overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
			);

      if (asset != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Overlay $tipo salvato in Galleria")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore salvataggio $tipo: $e")),
        );
      }
    }
  }

  // === API helper ===
  Future<void> _callAnalysis(String endpoint, String tipo) async {
    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/$endpoint");
      final req = http.MultipartRequest("POST", uri);
      req.files.add(
        await http.MultipartFile.fromPath("file", widget.imagePath),
      );
      req.fields["mode"] = widget.mode;

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      final decoded = await compute(jsonDecode, body);

      if (resp.statusCode == 200) {
        if (tipo == "all") {
          _parseRughe(decoded["analyze_rughe"]);
          _parseMacchie(decoded["analyze_macchie"]);
          _parseMelasma(decoded["analyze_melasma"]);
        } else if (tipo == "rughe") {
          _parseRughe(decoded);
        } else if (tipo == "macchie") {
          _parseMacchie(decoded);
        } else if (tipo == "melasma") {
          _parseMelasma(decoded);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Analisi $tipo completata")),
          );
        }
      } else {
        throw Exception("Errore server: ${resp.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore analisi: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // === Parsers ===
  void _parseRughe(dynamic data) {
    if (data == null) return;
    _rugheResult = data;
    _rugheOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _rughePercentuale =
        data["percentuale"] != null ? (data["percentuale"] as num).toDouble() : null;

    if (_rugheOverlayUrl != null) {
      _saveOverlayOnMain(url: _rugheOverlayUrl!, tipo: "rughe");
    }
  }

  void _parseMacchie(dynamic data) {
    if (data == null) return;
    _macchieResult = data;
    _macchieOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _macchiePercentuale =
        data["percentuale"] != null ? (data["percentuale"] as num).toDouble() : null;

    if (_macchieOverlayUrl != null) {
      _saveOverlayOnMain(url: _macchieOverlayUrl!, tipo: "macchie");
    }
  }

  void _parseMelasma(dynamic data) {
    if (data == null) return;
    _melasmaResult = data;
    _melasmaOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _melasmaPercentuale =
        data["percentuale"] != null ? (data["percentuale"] as num).toDouble() : null;

    if (_melasmaOverlayUrl != null) {
      _saveOverlayOnMain(url: _melasmaOverlayUrl!, tipo: "melasma");
    }
  }

  // === Blocchi UI ===
   Widget _buildAnalysisBlock({
    required String title,
    required String? overlayUrl,
    required double? percentuale,
    required String analysisType,
  }) {
    if (overlayUrl == null) return const SizedBox.shrink();

    final double side = MediaQuery.of(context).size.width * 0.9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "🔬 Analisi: $title",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 3),
          ),
          child: Image.network(
            overlayUrl,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) =>
                const Center(child: Text("Errore caricamento overlay")),
          ),
        ),
        const SizedBox(height: 10),
        if (percentuale != null)
          Text(
            "Percentuale area: ${percentuale.toStringAsFixed(2)}%",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        const SizedBox(height: 20),

        // 🔘 Pulsante per usare overlay e tornare al Pre/Post
        ElevatedButton.icon(
          onPressed: () async {
            try {
              final resp = await http.get(Uri.parse(overlayUrl));
              if (resp.statusCode == 200) {
                final dir = await Directory.systemTemp.createTemp();
                final file = File(
                  path.join(dir.path, "overlay_${analysisType}_${DateTime.now().millisecondsSinceEpoch}.png"),
                );
                await file.writeAsBytes(resp.bodyBytes);
                if (context.mounted) {
                  Navigator.pop(context, file);
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("❌ Errore scaricamento overlay")),
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("❌ Errore: $e")),
                );
              }
            }
          },
          icon: const Icon(Icons.check),
          label: const Text("Usa questo overlay"),
        ),

        const SizedBox(height: 20),

        const Text(
          "Come giudichi questa analisi? Dai un voto da 1 a 10",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(10, (index) {
            int voto = index + 1;
            return GestureDetector(
              onTap: () async {
                bool ok = await ApiService.sendJudgement(
                  filename: path.basename(widget.imagePath),
                  giudizio: voto,
                  analysisType: analysisType,
                  autore: "anonimo",
                );
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("✅ Giudizio $voto inviato per $analysisType"),
                    ),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$voto",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double side = MediaQuery.of(context).size.width * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == "particolare"
              ? "Anteprima (Particolare)"
              : "Anteprima (Volto intero)",
        ),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                // Foto originale
                Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 3),
                  ),
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),

                const SizedBox(height: 24),

                // 🔘 Pulsante "Analizza Tutto"
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _loading ? null : () => _callAnalysis("analyze_all", "all"),
                    child: const Text("Analizza Tutto"),
                  ),
                ),

                const SizedBox(height: 16),

                // 🔘 Riga pulsanti Rughe / Macchie / Melasma
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _callAnalysis("analyze_rughe", "rughe"),
                        child: const Text("Rughe"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _callAnalysis("analyze_macchie", "macchie"),
                        child: const Text("Macchie"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _callAnalysis("analyze_melasma", "melasma"),
                        child: const Text("Melasma"),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Blocchi analisi
                _buildAnalysisBlock(
                  title: "Rughe",
                  overlayUrl: _rugheOverlayUrl,
                  percentuale: _rughePercentuale,
                  analysisType: "rughe",
                ),
                _buildAnalysisBlock(
                  title: "Macchie",
                  overlayUrl: _macchieOverlayUrl,
                  percentuale: _macchiePercentuale,
                  analysisType: "macchie",
                ),
                _buildAnalysisBlock(
                  title: "Melasma",
                  overlayUrl: _melasmaOverlayUrl,
                  percentuale: _melasmaPercentuale,
                  analysisType: "melasma",
                ),
              ],
            ),
          ),

          if (_loading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
