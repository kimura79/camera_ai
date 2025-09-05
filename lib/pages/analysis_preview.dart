import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart'; // per compute
import 'package:google_fonts/google_fonts.dart';
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

  // === Funzione isolate per salvataggio overlay ===
  static Future<void> _saveOverlayIsolate(Map<String, String> params) async {
    final url = params["url"];
    final tipo = params["tipo"];
    if (url == null || tipo == null) return;

    final overlayResp = await http.get(Uri.parse(url));
    if (overlayResp.statusCode == 200) {
      final bytes = overlayResp.bodyBytes;
      final PermissionState pState =
          await PhotoManager.requestPermissionExtend();
      if (pState.isAuth) {
        await PhotoManager.editor.saveImage(
          bytes,
          filename:
              "overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
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

      if (resp.statusCode == 200) {
        final decoded = json.decode(body);

        if (tipo == "all") {
          _parseRughe(decoded["rughe"]);
          _parseMacchie(decoded["macchie"]);
          _parseMelasma(decoded["melasma"]);
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
      compute(_saveOverlayIsolate, {
        "url": _rugheOverlayUrl!,
        "tipo": "rughe",
      });
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
      compute(_saveOverlayIsolate, {
        "url": _macchieOverlayUrl!,
        "tipo": "macchie",
      });
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
      compute(_saveOverlayIsolate, {
        "url": _melasmaOverlayUrl!,
        "tipo": "melasma",
      });
    }
  }

  // === Blocchi UI ===
  Widget _buildAnalysisBlock({
    required String title,
    required String? overlayUrl,
    required double? percentuale,
    required String analysisType,
    required Color color,
  }) {
    if (overlayUrl == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "🔬 Analisi: $title",
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.mode == "particolare"
              ? "Anteprima (Particolare)"
              : "Anteprima (Volto intero)",
        ),
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
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),

            // 🔘 Pulsanti analisi in stile home page
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildActionButton(
                  text: "Analizza Rughe",
                  onTap: () => _callAnalysis("analyze_rughe", "rughe"),
                ),
                _buildActionButton(
                  text: "Analizza Macchie",
                  onTap: () => _callAnalysis("analyze_macchie", "macchie"),
                ),
                _buildActionButton(
                  text: "Analizza Melasma",
                  onTap: () => _callAnalysis("analyze_melasma", "melasma"),
                ),
                _buildActionButton(
                  text: "Analizza Tutto",
                  onTap: () => _callAnalysis("analyze_all", "all"),
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
              color: Colors.cyanAccent,
            ),
            _buildAnalysisBlock(
              title: "Macchie",
              overlayUrl: _macchieOverlayUrl,
              percentuale: _macchiePercentuale,
              analysisType: "macchie",
              color: Colors.orangeAccent,
            ),
            _buildAnalysisBlock(
              title: "Melasma",
              overlayUrl: _melasmaOverlayUrl,
              percentuale: _melasmaPercentuale,
              analysisType: "melasma",
              color: Colors.purpleAccent,
            ),
          ],
        ),
      ),
    );
  }

  // === Pulsanti custom stile HomePage ===
  Widget _buildActionButton({required String text, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: _loading ? Colors.white10 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _loading ? Colors.white24 : Colors.white,
            width: 1.5,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: _loading ? Colors.white38 : Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
