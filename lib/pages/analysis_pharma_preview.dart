import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:custom_camera_component/pages/analysis_pharma.dart';

/// ============================================================
/// 📸 ANALISI FARMACIA — analisi in background su schermo spento / cambio app
/// ============================================================
class AnalysisPharmaPreview extends StatefulWidget {
  final String imagePath;
  final String mode;
  const AnalysisPharmaPreview({
    super.key,
    required this.imagePath,
    this.mode = "fullface",
  });

  @override
  State<AnalysisPharmaPreview> createState() => _AnalysisPharmaPreviewState();
}

class _AnalysisPharmaPreviewState extends State<AnalysisPharmaPreview>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _serverReady = false;
  bool _showServerStatus = true;
  Timer? _retryTimer;
  final List<String> _serverUrls = ["http://46.101.223.88:5005"];
  String _activeServer = "";
  double _progress = 0.0;
  String? _currentJobId;
  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServer();
    _checkPendingJob(); // 🔹 Se c’è un job in corso, lo riprende dopo cambio app
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_isInBackground) {
      _cancelAllJobs(); // ✅ cancella solo se l’utente chiude app o torna indietro
    }
    _retryTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // 🔹 Gestione cicli vita app (screen off / app in background)
  // ============================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isInBackground = true;
      debugPrint("🌙 App in background → analisi continua sul server");
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      debugPrint("☀️ App ripresa → controllo job in corso...");
      _checkPendingJob();
    }
  }

  // ============================================================
  // 🔹 Controlla che il server farmacia sia online
  // ============================================================
  Future<void> _checkServer() async {
    for (final url in _serverUrls) {
      try {
        final resp = await http
            .get(Uri.parse("$url/status"))
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 &&
            jsonDecode(resp.body)["status"].toString().toLowerCase() == "ok") {
          setState(() {
            _serverReady = true;
            _activeServer = url;
            _showServerStatus = true;
          });
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => _showServerStatus = false);
          });
          return;
        }
      } catch (_) {}
    }
    setState(() {
      _serverReady = false;
      _showServerStatus = true;
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showServerStatus = false);
    });
    _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
  }

  // ============================================================
  // 🔹 Cancella job lato server e locale
  // ============================================================
  Future<void> _cancelAllJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jobId = _currentJobId ?? prefs.getString("last_job_id_farmacia");
      if (jobId != null && jobId.isNotEmpty && _activeServer.isNotEmpty) {
        final url = Uri.parse("$_activeServer/cancel_job/$jobId");
        await http.post(url).timeout(const Duration(seconds: 5));
        debugPrint("🛑 Job $jobId cancellato lato server");
      }
      await prefs.remove("last_job_id_farmacia");
      debugPrint("🧹 Pulizia job locale completata");
    } catch (e) {
      debugPrint("⚠️ Errore cancellazione job: $e");
    }
  }

  // ============================================================
  // 🔹 Invia immagine al server
  // ============================================================
  Future<void> _uploadAndAnalyze() async {
    if (!_serverReady || _activeServer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Server non pronto. Riprova tra pochi secondi."),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _progress = 0.02;
    });

    try {
      final uri = Uri.parse("$_activeServer/upload_async/farmacia");
      final request = http.MultipartRequest('POST', uri);
      request.headers['Connection'] = 'keep-alive';
      request.headers['Accept'] = 'application/json';
      request.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));

      debugPrint("📤 Upload in corso verso $_activeServer...");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🔍 Analisi avviata, attendere qualche secondo..."),
            duration: Duration(seconds: 3),
          ),
        );
      }

      final streamedResponse = await request.send();
      final respStr = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final jobId = jsonResp["job_id"];
        if (jobId == null) throw Exception("job_id non ricevuto dal server");
        _currentJobId = jobId;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("last_job_id_farmacia", jobId);

        await _pollJob(jobId);
        debugPrint("🚀 Job inviato con ID: $jobId");
      } else {
        throw Exception("Errore server (${streamedResponse.statusCode}): $respStr");
      }
    } catch (e) {
      debugPrint("❌ Errore analisi farmacia: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore durante l’analisi: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = 0.0;
          _serverReady = true;
        });
      }
    }
  }

  // ============================================================
  // 🔹 Polling continuo (no timeout)
  // ============================================================
  Future<void> _pollJob(String jobId) async {
    final dir = await getTemporaryDirectory();
    const pollingInterval = Duration(seconds: 2);
    int attempts = 0;

    while (mounted && !_isInBackground) {
      await Future.delayed(pollingInterval);
      final url = Uri.parse("$_activeServer/job/$jobId");
      http.Response resp;

      try {
        resp = await http.get(url);
      } catch (_) {
        continue;
      }

      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body);
      final status = data["status"];
      final progress = (data["progress"] ?? 0).toDouble();
      setState(() => _progress = progress / 100);

      if (status == "ready" || status == "done") {
        final result = data["result"];
        if (result == null) throw Exception("Risultato non trovato");

        final jsonFile = File("${dir.path}/result_farmacia.json");
        await jsonFile.writeAsString(jsonEncode(result));

        if (result["overlay_url"] != null) {
          final overlayResp = await http.get(Uri.parse(result["overlay_url"]));
          final overlayFile = File("${dir.path}/overlay_farmacia.png");
          await overlayFile.writeAsBytes(overlayResp.bodyBytes);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove("last_job_id_farmacia");
        _currentJobId = null;

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisPharmaPage(
              imagePath: widget.imagePath,
              jobId: jobId,
            ),
          ),
        );
        return;
      }

      if (status == "failed") throw Exception("Analisi fallita");
      attempts++;
    }
  }

  // ============================================================
  // 🔹 Riprende job se riapri app dopo schermo spento
  // ============================================================
  Future<void> _checkPendingJob() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString("last_job_id_farmacia");
    if (jobId != null && jobId.isNotEmpty && !_loading) {
      debugPrint("♻️ Riprendo polling per job: $jobId");
      _currentJobId = jobId;
      await _pollJob(jobId);
    }
  }

  // ============================================================
  // 🔹 UI con back che cancella job
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _cancelAllJobs(); // 🔥 Cancella tutto se back manuale
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A73E8),
          title: const Text("Analisi Farmacia"),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _cancelAllJobs(); // 🔥 Cancella tutto se back manuale
              Navigator.pop(context);
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(widget.imagePath),
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              if (_showServerStatus)
                (_serverReady
                    ? const Text(
                        "✅ Server connesso e pronto",
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w600),
                      )
                    : const Text(
                        "❌ Server non raggiungibile",
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w600),
                      )),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _serverReady && !_loading ? _uploadAndAnalyze : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: _loading
                        ? const Color(0xFFB3D5FF)
                        : const Color(0xFF1A73E8),
                  ),
                  child: Stack(
                    children: [
                      if (_loading)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: MediaQuery.of(context).size.width * _progress,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A73E8),
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      Center(
                        child: Text(
                          _loading
                              ? "Analisi ${(_progress * 100).toInt()}%"
                              : "Analizza Pelle",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
