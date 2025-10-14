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

// ✅ Funzione di polling asincrono: attende il completamento del job
Future<Map<String, dynamic>> waitForResult(String jobId) async {
  final url = Uri.parse("http://46.101.223.88:5000/status/$jobId");
  for (int i = 0; i < 180; i++) { // fino a 9 minuti di attesa
    final resp = await http.get(url);
    final data = jsonDecode(resp.body);
    if (data["status"] == "done") return data["result"];
    if (data["status"] == "error") throw Exception(data["result"]["error"]);
    await Future.delayed(const Duration(seconds: 3)); // ripeti ogni 3 secondi
  }
  throw Exception("Timeout analisi");
}

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

  // ✅ Variabile di stato per evitare chiamate multiple simultanee
bool _isCancelling = false;

// ✅ Funzione aggiornata per cancellare tutti i job attivi in sicurezza
Future<void> _cancelAllJobs() async {
  // Evita chiamate multiple contemporanee
  if (_isCancelling) {
    debugPrint("⚠️ Cancellazione già in corso, salto duplicato.");
    return;
  }

  _isCancelling = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      final jobId = prefs.getString("last_job_id_$tipo");
      if (jobId != null && jobId.isNotEmpty) {
        try {
          final url = Uri.parse("http://46.101.223.88:5000/cancel_job/$jobId");
          final resp = await http.post(url).timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200) {
            debugPrint("🛑 Job $jobId ($tipo) cancellato con successo lato server");
          } else {
            debugPrint("⚠️ Job $jobId ($tipo) non trovato o già completato (${resp.statusCode})");
          }
        } catch (e) {
          debugPrint("⚠️ Errore cancellazione job $jobId ($tipo): $e");
        }
      }
    }

    // ✅ Pulisce anche la cache locale dei job salvati
    for (final tipo in ["rughe", "macchie", "melasma", "pori"]) {
      await prefs.remove("last_job_id_$tipo");
    }
    debugPrint("🧹 Tutti i job e riferimenti locali puliti");
  } finally {
    _isCancelling = false;
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

  // === Funzioni per calcolare dimensioni immagine ===
  Future<Size> _getImageSizeFromUrl(String url) async {
    final completer = Completer<Size>();
    final imgWidget = Image.network(url);
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
      if (!granted) return;

      final String prefix = (widget.mode == "prepost") ? "POST" : "PRE";

      await PhotoManager.editor.saveImage(
        bytes,
        filename:
            "${prefix}_overlay_${tipo}_${DateTime.now().millisecondsSinceEpoch}.png",
      );
    } catch (_) {}
  }

  // === Chiamata async con retry, verifica file e polling ===
Future<void> _callAnalysisAsync(String tipo) async {
  // ✅ 1. Cancella eventuali job precedenti prima di lanciare una nuova analisi
  await _cancelAllJobs();
  await _clearPendingJobs();

  setState(() => _loading = true);
  try {
    // ✅ Copia l'immagine in percorso persistente
    final safePath = await copyToSafePath(widget.imagePath);
    final fileToSend = File(safePath);

    // ✅ Attendi che il file sia realmente scritto e > 100 KB
    bool ready = false;
    for (int i = 0; i < 10; i++) {
      if (await fileToSend.exists() && await fileToSend.length() > 100000) {
        ready = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!ready) {
      throw Exception("⚠️ File non pronto o vuoto: $safePath");
    }

    final uri = Uri.parse("http://46.101.223.88:5000/upload_async/$tipo");
    const int maxTentativi = 3;
    int tentativo = 0;
    http.StreamedResponse? resp;
    String? body;

    // ✅ Tentativi multipli con timeout e connessione chiusa
    while (tentativo < maxTentativi) {
      try {
        final req = http.MultipartRequest("POST", uri);
        req.files.add(await http.MultipartFile.fromPath("file", safePath));
        req.fields["mode"] = widget.mode;
        req.headers["Connection"] = "close"; // evita socket riusati

        debugPrint("📤 Invio analisi $tipo (tentativo ${tentativo + 1})...");
        resp = await req.send().timeout(const Duration(seconds: 90));
        body = await resp.stream.bytesToString();

        if (resp.statusCode == 200 && body.trim().startsWith("{")) break;
        debugPrint("⚠️ Tentativo ${tentativo + 1} fallito (HTTP ${resp.statusCode})");
      } catch (e) {
        debugPrint("⚠️ Errore tentativo ${tentativo + 1}: $e");
      }

      tentativo++;
      await Future.delayed(const Duration(seconds: 2));
    }

    if (resp == null || body == null || !body.trim().startsWith("{")) {
      throw Exception("❌ Server non raggiungibile dopo $maxTentativi tentativi");
    }

    // ✅ Decodifica risposta server e salva job ID
    final decoded = jsonDecode(body);
    if (decoded["job_id"] == null) {
      throw Exception("❌ Risposta server non valida: $body");
    }
    final String jobId = decoded["job_id"];
    debugPrint("🆔 Job avviato ($tipo): $jobId");

    // 🔹 Mostra messaggio visivo all'utente
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🚀 Analisi $tipo avviata")),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("last_job_id_$tipo", jobId);

    // ✅ Attendi completamento job (polling asincrono)
    final result = await waitForResult(jobId);
    if (result != null) {
      if (tipo == "rughe") _parseRughe(result);
      if (tipo == "macchie") _parseMacchie(result);
      if (tipo == "melasma") _parseMelasma(result);
      if (tipo == "pori") _parsePori(result);
    }

    // ✅ Pulisci job completato
    prefs.remove("last_job_id_$tipo");
  } catch (e) {
    debugPrint("❌ Errore analisi $tipo: $e");

    // ✅ 2. In caso di errore, pulisci e cancella i job rimasti
    await _cancelAllJobs();
    await _clearPendingJobs();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Errore analisi $tipo: $e")),
      );
    }
  } finally {
  if (mounted) setState(() => _loading = false);

  // ✅ Ritorno automatico a PrePostWidget appena completato l’overlay POST
  if (widget.mode == "prepost" && mounted) {
    // attende giusto un istante per assicurarsi che l’overlay sia salvato
    await Future.delayed(const Duration(milliseconds: 800));
    Navigator.pop(context, {"completed": true});
    debugPrint("✅ Ritorno automatico a PrePost completato");
  }
}
  }
}

  // ✅ Versione migliorata di _resumeJob che usa waitForResult()
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
      }
    } catch (e) {
      debugPrint("❌ Errore nel resumeJob ($tipo): $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    _numPoriVerdi = data["num_pori_verdi"] as int? ?? numNorm;
    _numPoriArancioni = data["num_pori_arancioni"] as int? ?? numBorder;
    _numPoriTotali = data["num_pori_totali"] as int? ?? (numNorm + numBorder + numDil);
    _percPoriDilatati = (data["perc_pori_dilatati"] as num?)?.toDouble();
    _poriFilename = data["filename"];
    if (_poriOverlayUrl != null) {
      await _saveOverlayOnMain(url: _poriOverlayUrl!, tipo: "pori");
    }
    if (mounted) setState(() {});
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
    if (overlayUrl == null || overlayUrl.isEmpty) {
      return const SizedBox.shrink();
    }

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
        Text(
          "🔬 Analisi: $title",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        FutureBuilder<Size>(
          future: _getImageSizeFromFilePath(widget.imagePath),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final originalSize = snapshot.data!;
            final aspect = originalSize.width / originalSize.height;
            return Container(
              color: Colors.black,
              width: double.infinity,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: aspect,
                child: InteractiveViewer(
                  clipBehavior: Clip.none,
                  minScale: 1.0,
                  maxScale: 10.0,
                  child: Image.network(
                    overlayUrl,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.center,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text(
                        "❌ Errore nel caricamento overlay",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
       if (analysisType == "pori" && numPoriTotali != null && numPoriTotali > 0) ...[
  Text(
    "Percentuale area totale pori: ${percentuale?.toStringAsFixed(2) ?? "0.00"}%",
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  const SizedBox(height: 6),
  Builder(
    builder: (_) {
      final percVerdi = (_numPoriVerdi ?? 0) / numPoriTotali * 100.0;
      final percArancioni = (_numPoriArancioni ?? 0) / numPoriTotali * 100.0;
      final percRossi = _percPoriDilatati ?? 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "🟢 Pori normali: ${percVerdi.toStringAsFixed(2)}%",
            style: const TextStyle(color: Colors.green, fontSize: 15),
          ),
          Text(
            "🟠 Pori borderline: ${percArancioni.toStringAsFixed(2)}%",
            style: const TextStyle(color: Colors.orange, fontSize: 15),
          ),
          Text(
            "🔴 Pori dilatati: ${percRossi.toStringAsFixed(2)}%",
            style: const TextStyle(color: Colors.red, fontSize: 15),
          ),
        ],
      );
    },
  ),
] else if (percentuale != null) ...[
  Text(
    "Percentuale area: ${percentuale.toStringAsFixed(2)}%",
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
],
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
                  filename: filename,
                  giudizio: voto,
                  analysisType: analysisType,
                  autore: "anonimo",
                );
                if (ok && mounted) {
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
                child: Text(
                  "$voto",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  Container(
                    color: Colors.black,
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = constraints.maxWidth;
                        return FutureBuilder<Size>(
                          future: _getImageSizeFromFilePath(widget.imagePath),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const SizedBox(
                                height: 200,
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final sz = snap.data!;
                            final aspect = sz.width / sz.height;
                            final displayW = maxW;
                            final displayH = displayW / aspect;
                            return SizedBox(
                              width: displayW,
                              height: displayH,
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                                alignment: Alignment.center,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
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
