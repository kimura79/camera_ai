import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
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
  final String mode; // "fullface" o "particolare" o "prepost"

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
  bool _serverReady = false;
  bool _checkingServer = true;

  Map<String, dynamic>? _rugheResult;
  String? _rugheOverlayUrl;
  double? _rughePercentuale;
  String? _rugheFilename;

  Map<String, dynamic>? _macchieResult;
  String? _macchieOverlayUrl;
  double? _macchiePercentuale;
  int? _numeroMacchie;
  String? _macchieFilename;

  Map<String, dynamic>? _melasmaResult;
  String? _melasmaOverlayUrl;
  double? _melasmaPercentuale;
  String? _melasmaFilename;

  Map<String, dynamic>? _poriResult;
  String? _poriOverlayUrl;
  double? _poriPercentuale;
  int? _numPoriTotali;
  double? _percPoriDilatati;
  String? _poriFilename;

  @override
  void initState() {
    super.initState();
    _clearPendingJobs();
    _checkPendingJobs();
    _checkServer();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // === 🔹 Cancella un singolo job lato server ===
  Future<void> _cancelJob(String jobId) async {
    try {
      final url = Uri.parse("http://46.101.223.88:5000/cancel_job/$jobId");
      await http.post(url);
      debugPrint("🛑 Job $jobId cancellato lato server");
    } catch (e) {
      debugPrint("⚠️ Errore cancellazione job $jobId: $e");
    }
  }

  Future<void> _cancelAllJobs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      final jobId = prefs.getString("last_job_id_$tipo");
      if (jobId != null && jobId.isNotEmpty) {
        await _cancelJob(jobId);
      }
    }
  }

  Future<void> _clearPendingJobs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      await prefs.remove("last_job_id_$tipo");
    }
    debugPrint("🧹 Pending jobs puliti");
  }

  Future<void> _checkServer() async {
    setState(() {
      _checkingServer = true;
    });

    try {
      final resp = await http
          .get(Uri.parse("http://46.101.223.88:5000/status"))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        setState(() {
          _serverReady = true;
          _checkingServer = false;
        });
        return;
      }
    } catch (_) {}

    setState(() {
      _serverReady = false;
      _checkingServer = false;
    });
    Future.delayed(const Duration(seconds: 3), _checkServer);
  }

  Future<void> _checkPendingJobs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      final jobId = prefs.getString("last_job_id_$tipo");
      if (jobId != null && jobId.isNotEmpty) {
        debugPrint("ℹ️ Riprendo job in corso: $tipo ($jobId)");
        await _resumeJob(tipo, jobId);
        break;
      }
    }
  }

  // === Salvataggio overlay ===
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

      final String prefix = (widget.mode == "prepost") ? "POST" : "PRE";

      await PhotoManager.editor.saveImage(
        bytes,
        filename:
            "${prefix}_overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Overlay $tipo pronto in galleria")),
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

  // === Chiamata async con polling ===
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
      req.fields["mode"] = widget.mode;

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode != 200 || !body.trim().startsWith("{")) {
        throw Exception("Risposta non valida dal server: $body");
      }

      final decoded = jsonDecode(body);
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
      try {
        final statusResp = await http
            .get(Uri.parse("http://46.101.223.88:5000/status/$jobId"))
            .timeout(const Duration(seconds: 10));
        if (statusResp.statusCode != 200) continue;

        final statusData = jsonDecode(statusResp.body);
        if (statusData["status"] == "done") {
          done = true;
          result = statusData["result"];
        } else if (statusData["status"] == "error") {
          done = true;
          result = {"error": statusData["result"]};
        }
      } catch (_) {
        continue;
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

        // 🔹 Se siamo in modalità PRE/POST → torna indietro con i dati dell’analisi
if (widget.mode == "prepost" && mounted) {
  final overlayUrl = result?["overlay_url"] != null
      ? "http://46.101.223.88:5000${result?["overlay_url"]}"
      : null;

  String? overlayPath;
  if (overlayUrl != null) {
    try {
      final resp = await http.get(Uri.parse(overlayUrl));
      if (resp.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        overlayPath = path.join(
          dir.path,
          "overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
        );
        await File(overlayPath).writeAsBytes(resp.bodyBytes);
      }
    } catch (e) {
      debugPrint("❌ Errore download overlay: $e");
    }
  }

  Navigator.pop(context, {
    "result": result,
    "overlay_path": overlayPath,
    "filename": result?["filename"],
    "analysisType": tipo,
  });
  return;
}
      }
    }

    // fallback: se sei in prepost e arrivi qui, chiudi comunque
    if (widget.mode == "prepost" && mounted) {
      Navigator.pop(context, {
        "result": result,
        "overlay_path": null,
        "id": null,
        "filename": null,
      });
      return;
    }

    if (mounted) setState(() => _loading = false);
  }

  // === Parsers ===
  void _parseRughe(dynamic data) async {
    _rugheResult = data;
    _rugheOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _rughePercentuale = (data["percentuale"] as num?)?.toDouble();
    _rugheFilename = data["filename"];
    if (_rugheOverlayUrl != null) {
      await _saveOverlayOnMain(url: _rugheOverlayUrl!, tipo: "rughe");
    }
  }

  void _parseMacchie(dynamic data) async {
    _macchieResult = data;
    _macchieOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _macchiePercentuale = (data["percentuale"] as num?)?.toDouble();
    _numeroMacchie = data["numero_macchie"] as int?;
    _macchieFilename = data["filename"];
    if (_macchieOverlayUrl != null) {
      await _saveOverlayOnMain(url: _macchieOverlayUrl!, tipo: "macchie");
    }
  }

  void _parseMelasma(dynamic data) async {
    _melasmaResult = data;
    _melasmaOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _melasmaPercentuale = (data["percentuale"] as num?)?.toDouble();
    _melasmaFilename = data["filename"];
    if (_melasmaOverlayUrl != null) {
      await _saveOverlayOnMain(url: _melasmaOverlayUrl!, tipo: "melasma");
    }
  }

  void _parsePori(dynamic data) async {
    _poriResult = data;
    _poriOverlayUrl = data["overlay_url"] != null
        ? "http://46.101.223.88:5000${data["overlay_url"]}"
        : null;
    _poriPercentuale = (data["percentuale"] as num?)?.toDouble();
    final numNorm = data["num_pori_normali"] as int? ?? 0;
    final numBorder = data["num_pori_borderline"] as int? ?? 0;
    final numDil = data["num_pori_dilatati"] as int? ?? 0;
    _numPoriTotali = numNorm + numBorder + numDil;
    _percPoriDilatati = (data["perc_pori_dilatati"] as num?)?.toDouble();
    _poriFilename = data["filename"];
    if (_poriOverlayUrl != null) {
      await _saveOverlayOnMain(url: _poriOverlayUrl!, tipo: "pori");
    }
  }

  // === Blocchi UI ===
  Widget _buildAnalysisBlock({
    required String title,
    required String? overlayUrl,
    required double? percentuale,
    required String analysisType,
    int? numeroMacchie,
    int? numPoriTotali,
    double? percPoriDilatati,
  }) {
    if (overlayUrl == null) return const SizedBox.shrink();

    final double side = MediaQuery.of(context).size.width * 0.9;

    // ✅ Ricava filename corretto in base all'analisi
    String filename = analysisType == "rughe"
        ? (_rugheFilename ?? path.basename(widget.imagePath))
        : analysisType == "macchie"
            ? (_macchieFilename ?? path.basename(widget.imagePath))
            : analysisType == "melasma"
                ? (_melasmaFilename ?? path.basename(widget.imagePath))
                : (_poriFilename ?? path.basename(widget.imagePath));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text("🔬 Analisi: $title",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 3),
          ),
          child: Image.network(overlayUrl, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        if (percentuale != null)
          Text("Percentuale area: ${percentuale.toStringAsFixed(2)}%",
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
        if (numeroMacchie != null)
          Text("Numero macchie: $numeroMacchie",
              style: const TextStyle(fontSize: 16)),
        if (numPoriTotali != null)
          Text("Totale pori: $numPoriTotali",
              style: const TextStyle(fontSize: 16)),
        if (percPoriDilatati != null)
          Text("Pori dilatati: ${percPoriDilatati.toStringAsFixed(2)}%",
              style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 20),

        // 🔹 Sezione giudizi
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
                      content:
                          Text("✅ Giudizio $voto inviato per $analysisType"),
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

    return WillPopScope(
      onWillPop: () async {
        await _cancelAllJobs();
        await _clearPendingJobs();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.mode == "particolare"
                ? "Anteprima (Particolare)"
                : widget.mode == "prepost"
                    ? "Anteprima (Pre/Post)"
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
                    child: Image.file(File(widget.imagePath),
                        fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 24),
                  if (_checkingServer)
                    const CircularProgressIndicator()
                  else if (!_serverReady)
                    Column(
                      children: [
                        const Text("❌ Server non raggiungibile"),
                        ElevatedButton(
                          onPressed: _checkServer,
                          child: const Text("Riprova"),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_loading || !_serverReady)
                              ? null
                              : () => _callAnalysisAsync("rughe"),
                          child: const Text("Rughe"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_loading || !_serverReady)
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
                          onPressed: (_loading || !_serverReady)
                              ? null
                              : () => _callAnalysisAsync("melasma"),
                          child: const Text("Melasma"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_loading || !_serverReady)
                              ? null
                              : () => _callAnalysisAsync("pori"),
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
                    numeroMacchie: _numeroMacchie,
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
                    numPoriTotali: _numPoriTotali,
                    percPoriDilatati: _percPoriDilatati,
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
      ),
    );
  }
}
