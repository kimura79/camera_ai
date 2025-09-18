import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart'; // per compute JSON
import 'package:custom_camera_component/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🔹 Copia la foto in un percorso sicuro che resta valido anche a schermo spento
Future<String> copyToSafePath(String originalPath) async {
  final dir = await getApplicationDocumentsDirectory();
  final safePath = path.join(
    dir.path,
    "photo_${DateTime.now().millisecondsSinceEpoch}.jpg",
  );
  final originalFile = File(originalPath);
  await originalFile.copy(safePath);
  return safePath;
}

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

  Map<String, dynamic>? _poriResult;
  String? _poriOverlayUrl;
  double? _poriPercentuale;

  String? _rugheFilename;
  String? _macchieFilename;
  String? _melasmaFilename;
  String? _poriFilename;

  @override
void initState() {
  super.initState();
  _checkPendingJobs();
}

Future<void> _checkPendingJobs() async {
  final prefs = await SharedPreferences.getInstance();
  for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
    final jobId = prefs.getString("last_job_id_$tipo");
    if (jobId != null && jobId.isNotEmpty) {
      debugPrint("ℹ️ Riprendo job in corso: $tipo ($jobId)");
      await _resumeJob(tipo, jobId);
      break; // riprendo solo il primo job trovato
    }
  }
}

  // === Salvataggio overlay in galleria (senza chiudere pagina) ===
  Future<void> _saveOverlayOnMain({
    required String url,
    required String tipo,
  }) async {
    try {
      final overlayResp = await http.get(Uri.parse(url));
      if (overlayResp.statusCode != 200) return;

      final bytes = overlayResp.bodyBytes;

      final PermissionState pState =
          await PhotoManager.requestPermissionExtend();
      final bool granted = pState.isAuth || pState.hasAccess;
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Permesso galleria negato")),
        );
        return;
      }

      await PhotoManager.editor.saveImage(
        bytes,
        filename:
            "overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Overlay $tipo pronto")),
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

  // === API helper sincrono (non usato in async) ===
  Future<void> _callAnalysis(String endpoint, String tipo) async {
    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/$endpoint");
      final req = http.MultipartRequest("POST", uri);
      final safePath = await copyToSafePath(widget.imagePath);
      req.files.add(
        await http.MultipartFile.fromPath(
          "file",
          safePath,
          filename: path.basename(safePath),
        ),
      );
      req.fields["mode"] = widget.mode;

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(body);

        if (tipo == "rughe") _parseRughe(decoded);
        if (tipo == "macchie") _parseMacchie(decoded);
        if (tipo == "melasma") _parseMelasma(decoded);
        if (tipo == "pori") _parsePori(decoded);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Analisi $tipo completata")),
          );
        }
      } else {
        throw Exception("Errore server: ${resp.statusCode}\n$body");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore analisi: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // === Chiamata asincrona con job_id + polling ===
  Future<void> _callAnalysisAsync(String tipo) async {
    setState(() => _loading = true);
    try {
      final safePath = await copyToSafePath(widget.imagePath);

      final uri = Uri.parse("http://46.101.223.88:5000/upload_async/$tipo");
      final req = http.MultipartRequest("POST", uri);
      req.files.add(
        await http.MultipartFile.fromPath(
          "file",
          safePath,
          filename: path.basename(safePath),
        ),
      );

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode != 200 || !body.trim().startsWith("{")) {
        throw Exception("Risposta non valida dal server: $body");
      }

      final decoded = jsonDecode(body);
      if (decoded["job_id"] == null) {
        throw Exception("Job ID mancante nella risposta");
      }
      final String jobId = decoded["job_id"];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("last_job_id_$tipo", jobId);

      await _resumeJob(tipo, jobId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore analisi: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resumeJob(String tipo, String jobId) async {
    setState(() => _loading = true);

    bool done = false;
    Map<String, dynamic>? result;

    while (!done && mounted) {
      await Future.delayed(const Duration(seconds: 2));
      final statusResp =
          await http.get(Uri.parse("http://46.101.223.88:5000/status/$jobId"));
      if (statusResp.statusCode != 200) continue;

      final statusData = jsonDecode(statusResp.body);
      if (statusData["status"] == "done") {
        done = true;
        result = statusData["result"];
      } else if (statusData["status"] == "error") {
        done = true;
        result = {"error": statusData["result"]};
      }
    }

    if (result != null) {
      if (tipo == "rughe") _parseRughe(result);
      if (tipo == "macchie") _parseMacchie(result);
      if (tipo == "melasma") _parseMelasma(result);
      if (tipo == "pori") _parsePori(result);

      final prefs = await SharedPreferences.getInstance();
      prefs.remove("last_job_id_$tipo");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Analisi $tipo completata")),
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  // === Parsers ===
  void _parseRughe(dynamic data) {
    if (data == null) return;
    _rugheResult = data;
    _rugheOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _rughePercentuale = data["percentuale"] != null
        ? (data["percentuale"] as num).toDouble()
        : null;
    _rugheFilename = data["filename"];
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
    _macchiePercentuale = data["percentuale"] != null
        ? (data["percentuale"] as num).toDouble()
        : null;
    _macchieFilename = data["filename"];
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
    _melasmaPercentuale = data["percentuale"] != null
        ? (data["percentuale"] as num).toDouble()
        : null;
    _melasmaFilename = data["filename"];
    if (_melasmaOverlayUrl != null) {
      _saveOverlayOnMain(url: _melasmaOverlayUrl!, tipo: "melasma");
    }
  }

  void _parsePori(dynamic data) {
    if (data == null) return;
    _poriResult = data;
    _poriOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _poriPercentuale = data["percentuale"] != null
        ? (data["percentuale"] as num).toDouble()
        : null;
    _poriFilename = data["filename"];
    if (_poriOverlayUrl != null) {
      _saveOverlayOnMain(url: _poriOverlayUrl!, tipo: "pori");
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

      const Text(
        "Come giudichi questa analisi? Dai un voto da 1 a 10",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),

      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(10, (index) {
          int voto = index + 1;

          // ✅ Usa filename reale se esiste, altrimenti fallback
          String filename = analysisType == "rughe"
              ? (_rugheFilename ?? path.basename(widget.imagePath))
              : analysisType == "macchie"
                  ? (_macchieFilename ?? path.basename(widget.imagePath))
                  : analysisType == "melasma"
                      ? (_melasmaFilename ?? path.basename(widget.imagePath))
                      : (_poriFilename ?? path.basename(widget.imagePath));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              bool ok = await ApiService.sendJudgement(
                filename: filename,
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _loading ? null : () => _callAnalysisAsync("rughe"),
                        child: const Text("Rughe"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _callAnalysisAsync("macchie"),
                        child: const Text("Macchie"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _callAnalysisAsync("melasma"),
                        child: const Text("Melasma"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _loading ? null : () => _callAnalysisAsync("pori"),
                        child: const Text("Pori"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                _buildAnalysisBlock(
                  title: "Pori",
                  overlayUrl: _poriOverlayUrl,
                  percentuale: _poriPercentuale,
                  analysisType: "pori",
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
