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

// =====================================================
// === Utility: copia immagine in percorso sicuro ======
// =====================================================
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

// =====================================================
// === Utility: polling asincrono ======================
// =====================================================
Future<Map<String, dynamic>> waitForResult(String jobId) async {
  final url = Uri.parse("http://46.101.223.88:5000/status/$jobId");
  for (int i = 0; i < 300; i++) {
    final resp = await http.get(url);
    final data = jsonDecode(resp.body);
    if (data["status"] == "done") return data["result"];
    if (data["status"] == "error") throw Exception(data["result"]["error"]);
    await Future.delayed(const Duration(seconds: 3));
  }
  throw Exception("Timeout analisi");
}

// =====================================================
// === Pagina principale ===============================
// =====================================================
class AnalysisPreview extends StatefulWidget {
  final String imagePath;
  final String mode; // fullface / particolare / prepost

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

  // =====================================================
  // === INIT ===========================================
  // =====================================================
  @override
  void initState() {
    super.initState();
    _clearPendingJobs();
    _checkPendingJobs();
    _checkServer();
  }

  // =====================================================
  // === JOB MANAGEMENT ================================
  // =====================================================
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

  // =====================================================
  // === UTILITIES ======================================
  // =====================================================
  Future<Size> _getImageSizeFromFilePath(String filePath) async {
    final completer = Completer<Size>();
    final imgWidget = Image.file(File(filePath));
    final stream = imgWidget.image.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((ImageInfo info, _) {
      completer.complete(Size(info.image.width.toDouble(), info.image.height.toDouble()));
      stream.removeListener(listener);
    }, onError: (_, __) {
      completer.complete(const Size(1024, 1024));
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _saveOverlayOnMain({required String url, required String tipo}) async {
    try {
      final overlayResp = await http.get(Uri.parse(url));
      if (overlayResp.statusCode != 200) return;
      final bytes = overlayResp.bodyBytes;
      final PermissionState pState = await PhotoManager.requestPermissionExtend();
      if (!(pState.isAuth || pState.hasAccess)) return;
      final String prefix = (widget.mode == "prepost") ? "POST" : "PRE";
      await PhotoManager.editor.saveImage(
        bytes,
        filename: "${prefix}_overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
      );
    } catch (_) {}
  }

  // =====================================================
  // === CHIAMATA ASINCRONA PRINCIPALE ===================
  // =====================================================
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
        throw Exception("Risposta non valida: $body");
      }
      final decoded = jsonDecode(body);
      final String jobId = decoded["job_id"];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("last_job_id_$tipo", jobId);
      final result = await waitForResult(jobId);
      await prefs.remove("last_job_id_$tipo");
      if (tipo == "rughe") _parseRughe(result);
      if (tipo == "macchie") _parseMacchie(result);
      if (tipo == "melasma") _parseMelasma(result);
      if (tipo == "pori") _parsePori(result);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("✅ Analisi $tipo completata")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ Errore analisi: $e")));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =====================================================
  // === PARSER RISULTATI ================================
  // =====================================================
  void _parseRughe(dynamic data) async {
    _rugheResult = data;
    _rugheOverlayUrl = "http://46.101.223.88:5000${data["overlay_url"]}";
    _rughePercentuale = (data["percentuale"] as num?)?.toDouble();
    _rugheFilename = data["filename"];
    await _saveOverlayOnMain(url: _rugheOverlayUrl!, tipo: "rughe");
    setState(() {});
  }

  void _parseMacchie(dynamic data) async {
    _macchieResult = data;
    _macchieOverlayUrl = "http://46.101.223.88:5000${data["overlay_url"]}";
    _macchiePercentuale = (data["percentuale"] as num?)?.toDouble();
    _numeroMacchie = data["numero_macchie"] as int?;
    _macchieFilename = data["filename"];
    await _saveOverlayOnMain(url: _macchieOverlayUrl!, tipo: "macchie");
    setState(() {});
  }

  void _parseMelasma(dynamic data) async {
    _melasmaResult = data;
    _melasmaOverlayUrl = "http://46.101.223.88:5000${data["overlay_url"]}";
    _melasmaPercentuale = (data["percentuale"] as num?)?.toDouble();
    _melasmaFilename = data["filename"];
    await _saveOverlayOnMain(url: _melasmaOverlayUrl!, tipo: "melasma");
    setState(() {});
  }

  void _parsePori(dynamic data) async {
    _poriResult = data;
    _poriOverlayUrl = "http://46.101.223.88:5000${data["overlay_url"]}";
    _poriPercentuale = (data["percentuale"] as num?)?.toDouble();
    _numPoriTotali = data["num_pori_totali"] as int?;
    _percPoriDilatati = (data["perc_pori_dilatati"] as num?)?.toDouble();
    _numPoriVerdi = data["num_pori_normali"] as int?;
    _numPoriArancioni = data["num_pori_borderline"] as int?;
    _poriFilename = data["filename"];
    await _saveOverlayOnMain(url: _poriOverlayUrl!, tipo: "pori");
    setState(() {});
  }

  // =====================================================
  // === UI: BLOCCO RISULTATI + VOTO =====================
  // =====================================================
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
          color: Colors.black,
          width: double.infinity,
          alignment: Alignment.center,
          child: InteractiveViewer(
            clipBehavior: Clip.none,
            minScale: 1.0,
            maxScale: 10.0,
            child: Image.network(overlayUrl, fit: BoxFit.fitWidth),
          ),
        ),
        const SizedBox(height: 10),
        if (percentuale != null)
          Text("Percentuale area: ${percentuale.toStringAsFixed(2)}%"),
        if (numeroMacchie != null) Text("Numero macchie: $numeroMacchie"),
        if (numPoriTotali != null)
          Text("Totale pori: $numPoriTotali (${percPoriDilatati?.toStringAsFixed(2)}% dilatati)"),
        const SizedBox(height: 20),
        const Text("Come giudichi questa analisi? Dai un voto da 1 a 10",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(10, (i) {
            final voto = i + 1;
            return GestureDetector(
              onTap: () async {
                await ApiService.sendJudgement(
                  filename: filename,
                  giudizio: voto,
                  analysisType: analysisType,
                  autore: "auto",
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ Giudizio $voto inviato per $analysisType")),
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
                child: Text("$voto", style: const TextStyle(color: Colors.white)),
              ),
            );
          }),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // =====================================================
  // === BUILD UI COMPLETA ===============================
  // =====================================================
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
          title: Text(
            widget.mode == "particolare"
                ? "Anteprima (Particolare)"
                : widget.mode == "prepost"
                    ? "Anteprima (Pre/Post)"
                    : "Anteprima Analisi",
          ),
          backgroundColor: Colors.blue,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ✅ FOTO ORIGINALE
                  Container(
                    color: Colors.black,
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 16),

                  // ✅ SERVER STATUS
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

                  // ✅ PULSANTI ANALISI
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

                  // ✅ RISULTATI
                  _buildAnalysisBlock(
                      title: "Rughe",
                      overlayUrl: _rugheOverlayUrl,
                      percentuale: _rughePercentuale,
                      analysisType: "rughe"),
                  _buildAnalysisBlock(
                      title: "Macchie",
                      overlayUrl: _macchieOverlayUrl,
                      percentuale: _macchiePercentuale,
                      analysisType: "macchie",
                      numeroMacchie: _numeroMacchie),
                  _buildAnalysisBlock(
                      title: "Melasma",
                      overlayUrl: _melasmaOverlayUrl,
                      percentuale: _melasmaPercentuale,
                      analysisType: "melasma"),
                  _buildAnalysisBlock(
                      title: "Pori",
                      overlayUrl: _poriOverlayUrl,
                      percentuale: _poriPercentuale,
                      analysisType: "pori",
                      numPoriTotali: _numPoriTotali,
                      percPoriDilatati: _percPoriDilatati),
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