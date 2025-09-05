import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart'; // per compute
import 'package:custom_camera_component/services/api_service.dart';

class AnalysisPreview extends StatefulWidget {
  final String imagePath;
  final String mode; // "fullface" o "particolare" per le rughe

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

  // === Funzione isolate per salvataggio overlay ===
  static Future<void> _saveOverlayIsolate(Map<String, String> params) async {
    final url = params["url"];
    final tipo = params["tipo"];
    if (url == null || tipo == null) return;

    final overlayResp = await http.get(Uri.parse(url));
    if (overlayResp.statusCode == 200) {
      final bytes = overlayResp.bodyBytes;
      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (pState.isAuth) {
        await PhotoManager.editor.saveImage(
          bytes,
          filename: "overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
        );
      }
    }
  }

  Future<void> _analyzeImage() async {
    setState(() {
      _loading = true;
      _rugheResult = null;
      _rugheOverlayUrl = null;
      _rughePercentuale = null;
      _macchieResult = null;
      _macchieOverlayUrl = null;
      _macchiePercentuale = null;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/analyze_all");
      final req = http.MultipartRequest("POST", uri);
      req.files.add(
        await http.MultipartFile.fromPath("file", widget.imagePath),
      );

      // 🔹 Invia sempre il mode scelto (fullface o particolare)
      req.fields["mode"] = widget.mode;

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 200) {
        final decoded = json.decode(body);

        // Rughe
        if (decoded["rughe"] != null) {
          _rugheResult = decoded["rughe"];
          _rugheOverlayUrl = decoded["rughe"]["overlay_url"] != null
              ? "http://46.101.223.88:5000${decoded["rughe"]["overlay_url"]}"
              : null;
          _rughePercentuale = decoded["rughe"]["percentuale"] != null
              ? (decoded["rughe"]["percentuale"] as num).toDouble()
              : null;
        }

        // Macchie
        if (decoded["macchie"] != null) {
          _macchieResult = decoded["macchie"];
          _macchieOverlayUrl = decoded["macchie"]["overlay_url"] != null
              ? "http://46.101.223.88:5000${decoded["macchie"]["overlay_url"]}"
              : null;
          _macchiePercentuale = decoded["macchie"]["percentuale"] != null
              ? (decoded["macchie"]["percentuale"] as num).toDouble()
              : null;
        }

        // 🔐 Salvataggio overlay in background isolate
        if (_rugheOverlayUrl != null) {
          compute(_saveOverlayIsolate, {
            "url": _rugheOverlayUrl!,
            "tipo": "rughe",
          });
        }
        if (_macchieOverlayUrl != null) {
          compute(_saveOverlayIsolate, {
            "url": _macchieOverlayUrl!,
            "tipo": "macchie",
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Analisi completata")),
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

  Widget _buildAnalysisBlock({
    required String title,
    required String? overlayUrl,
    required double? percentuale,
    required String analysisType,
  }) {
    if (overlayUrl == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "🔬 Analisi: $title",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 3),
          ),
          child: Image.network(
            overlayUrl,
            fit: BoxFit.cover,
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
                      content: Text(
                          "✅ Giudizio $voto inviato per $analysisType"),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == "particolare"
              ? "Anteprima (Particolare)"
              : "Anteprima (Volto intero)",
        ),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // Foto originale
            Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
              ),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),

            // 🔘 Un solo pulsante "Analizza"
            ElevatedButton(
              onPressed: _loading ? null : _analyzeImage,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Analizza"),
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
          ],
        ),
      ),
    );
  }
}
