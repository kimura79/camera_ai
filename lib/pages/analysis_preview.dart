import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:custom_camera_component/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Polling asincrono stabile
Future<Map<String, dynamic>> waitForResult(String jobId) async {
  final url = Uri.parse("http://46.101.223.88:5000/status/$jobId");
  for (int i = 0; i < 180; i++) {
    final resp = await http.get(url);
    final data = jsonDecode(resp.body);
    if (data["status"] == "done") return data["result"];
    if (data["status"] == "error") throw Exception(data["result"]["error"]);
    await Future.delayed(const Duration(seconds: 3));
  }
  throw Exception("Timeout analisi");
}

// 🔹 Copia la foto in un percorso sicuro
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
  final String mode;

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
  int? _numPoriVerdi;
  int? _numPoriArancioni;
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

  // 🔹 Cancella job
  Future<void> _cancelJob(String jobId) async {
    try {
      await http.post(Uri.parse("http://46.101.223.88:5000/cancel_job/$jobId"));
    } catch (_) {}
  }

  Future<void> _cancelAllJobs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      final jobId = prefs.getString("last_job_id_$tipo");
      if (jobId != null && jobId.isNotEmpty) await _cancelJob(jobId);
    }
  }

  Future<void> _clearPendingJobs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      await prefs.remove("last_job_id_$tipo");
    }
  }

  Future<void> _checkServer() async {
    setState(() => _checkingServer = true);
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
        await _resumeJob(tipo, jobId);
        break;
      }
    }
  }

  // === Funzioni per calcolare dimensioni immagine ===
  Future<Size> _getImageSizeFromFilePath(String filePath) async {
    final completer = Completer<Size>();
    final imgWidget = Image.file(File(filePath));
    final ImageStream stream = imgWidget.image.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((ImageInfo info, bool _) {
      completer.complete(Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      ));
      stream.removeListener(listener);
    }, onError: (dynamic _, __) {
      completer.complete(const Size(1024, 1024));
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  // === Chiamata async con polling ===
  Future<void> _callAnalysisAsync(String tipo) async {
    setState(() => _loading = true);
    try {
      final safePath = await copyToSafePath(widget.imagePath);
      final uri = Uri.parse("http://46.101.223.88:5000/upload_async/$tipo");
      final req = http.MultipartRequest("POST", uri);
      req.files.add(await http.MultipartFile.fromPath("file", safePath));
      req.fields["mode"] = widget.mode;
      final resp = await req.send();
      final body = await resp.stream.bytesToString();
      if (resp.statusCode != 200 || !body.trim().startsWith("{")) {
        throw Exception("Risposta non valida dal server");
      }
      final decoded = jsonDecode(body);
      final jobId = decoded["job_id"];
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

  // ✅ Versione con waitForResult()
  Future<void> _resumeJob(String tipo, String jobId) async {
    setState(() => _loading = true);
    try {
      final result = await waitForResult(jobId);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore $tipo: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // === Parsers ===
  void _parseRughe(dynamic data) {
    _rugheResult = data;
    _rugheOverlayUrl =
        "http://46.101.223.88:5000${data["overlay_url"] ?? ""}";
    _rughePercentuale = (data["percentuale"] as num?)?.toDouble();
    _rugheFilename = data["filename"];
    setState(() {});
  }

  void _parseMacchie(dynamic data) {
    _macchieResult = data;
    _macchieOverlayUrl =
        "http://46.101.223.88:5000${data["overlay_url"] ?? ""}";
    _macchiePercentuale = (data["percentuale"] as num?)?.toDouble();
    _numeroMacchie = data["numero_macchie"] as int?;
    _macchieFilename = data["filename"];
    setState(() {});
  }

  void _parseMelasma(dynamic data) {
    _melasmaResult = data;
    _melasmaOverlayUrl =
        "http://46.101.223.88:5000${data["overlay_url"] ?? ""}";
    _melasmaPercentuale = (data["percentuale"] as num?)?.toDouble();
    _melasmaFilename = data["filename"];
    setState(() {});
  }

  void _parsePori(dynamic data) {
    _poriResult = data;
    _poriOverlayUrl =
        "http://46.101.223.88:5000${data["overlay_url"] ?? ""}";
    _poriPercentuale = (data["percentuale"] as num?)?.toDouble();
    _numPoriTotali = data["num_pori_totali"];
    _percPoriDilatati = (data["perc_pori_dilatati"] as num?)?.toDouble();
    setState(() {});
  }

  // === Blocchi UI con voti ===
  Widget _buildAnalysisBlock({
    required String title,
    required String? overlayUrl,
    required double? percentuale,
    required String analysisType,
    int? numeroMacchie,
    int? numPoriTotali,
    double? percPoriDilatati,
  }) {
    if (overlayUrl == null || overlayUrl.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text("🔬 Analisi: $title",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: Image.network(overlayUrl, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        if (percentuale != null)
          Text("Percentuale area: ${percentuale.toStringAsFixed(2)}%"),
        if (numeroMacchie != null)
          Text("Numero macchie: $numeroMacchie"),
        if (numPoriTotali != null)
          Text("Totale pori: $numPoriTotali"),
        if (percPoriDilatati != null)
          Text("Pori dilatati: ${percPoriDilatati.toStringAsFixed(2)}%"),
        const SizedBox(height: 20),

        // 🔹 Voti utente (1–10)
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
                    SnackBar(content: Text("✅ Giudizio $voto inviato")),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text("$voto",
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
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
    return WillPopScope(
      onWillPop: () async {
        await _cancelAllJobs();
        await _clearPendingJobs();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Anteprima Analisi"),
          backgroundColor: Colors.blue,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}