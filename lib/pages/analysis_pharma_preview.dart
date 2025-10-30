import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:custom_camera_component/pages/analysis_pharma.dart';

/// ============================================================
/// 📸 ANALISI FARMACIA (asincrona con job polling + barra fluida)
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
    with TickerProviderStateMixin {
  bool _loading = false;
  bool _serverReady = false;
  bool _showServerStatus = true;
  Timer? _retryTimer;
  final List<String> _serverUrls = ["http://46.101.223.88:5005"];
  String _activeServer = "";

  double _progress = 0.0;
  late AnimationController _animController;
  late Animation<double> _animProgress;

  @override
  void initState() {
    super.initState();
    _checkServer();

    // 🔹 Inizializza animazione fluida per la barra
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animProgress = Tween<double>(begin: 0.0, end: 0.0).animate(_animController)
      ..addListener(() {
        if (mounted) setState(() => _progress = _animProgress.value);
      });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ============================================================
  // 🔹 Controlla server farmacia
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
  // 🔹 Upload immagine e avvio analisi
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
      request.files.add(
        await http.MultipartFile.fromPath('file', widget.imagePath),
      );

      http.StreamedResponse streamedResponse;
      try {
        streamedResponse =
            await request.send().timeout(const Duration(seconds: 90));
      } on TimeoutException {
        debugPrint("⏰ Timeout durante upload — nuovo tentativo...");
        await Future.delayed(const Duration(seconds: 2));
        return _uploadAndAnalyze();
      }

      final respStr = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final jobId = jsonResp["job_id"];
        if (jobId == null) throw Exception("job_id non ricevuto dal server");

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🔍 Analisi avviata, attendere qualche secondo..."),
            duration: Duration(seconds: 3),
          ),
        );

        await _pollJob(jobId);
      } else {
        throw Exception(
            "Errore server (${streamedResponse.statusCode}): $respStr");
      }
    } catch (e) {
      debugPrint("❌ Errore analisi farmacia: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore durante l’analisi: $e"),
            backgroundColor: Colors.redAccent,
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
  // 🔹 Polling job con barra dinamica
  // ============================================================
  Future<void> _pollJob(String jobId) async {
    final dir = await getTemporaryDirectory();
    const pollingInterval = Duration(seconds: 2);

    while (mounted) {
      await Future.delayed(pollingInterval);
      final url = Uri.parse("$_activeServer/job/$jobId");

      http.Response resp;
      try {
        resp = await http.get(url).timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint("⚠️ Errore polling: $e");
        continue;
      }

      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body);
      final status = data["status"];
      final progress = (data["progress"] ?? 0).toDouble();

      // 🔹 aggiorna animazione fluida
      if (mounted) {
        _animController.stop();
        _animController.reset();
        _animProgress = Tween<double>(
          begin: _progress,
          end: (progress / 100).clamp(0.0, 1.0),
        ).animate(CurvedAnimation(
          parent: _animController,
          curve: Curves.easeInOut,
        ));
        _animController.forward();
      }

      debugPrint("⏱️ Stato job $jobId: $status (${progress.toStringAsFixed(1)}%)");

      if (status == "ready" || status == "done") {
        final result = data["result"];
        if (result == null) throw Exception("Risultato non trovato");

        setState(() => _progress = 1.0);
        await Future.delayed(const Duration(milliseconds: 800));

        final jsonFile = File("${dir.path}/result_farmacia.json");
        await jsonFile.writeAsString(jsonEncode(result));

        if (result["overlay_url"] != null) {
          final overlayResp = await http.get(Uri.parse(result["overlay_url"]));
          final overlayFile = File("${dir.path}/overlay_farmacia.png");
          await overlayFile.writeAsBytes(overlayResp.bodyBytes);
          debugPrint("🖼️ Overlay salvato: ${overlayFile.path}");
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Analisi completata!"),
            duration: Duration(seconds: 3),
          ),
        );

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

      if (status == "failed") {
        final errorMsg = data["error"] ?? "Analisi fallita";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Analisi fallita: $errorMsg"),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }
  }

  // ============================================================
  // 🔹 UI principale
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text("Analisi Farmacia"),
        centerTitle: true,
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
                  ? const Text("✅ Server connesso e pronto",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w600))
                  : const Text("❌ Server non raggiungibile",
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600))),

            const SizedBox(height: 10),

            // 🔹 Pulsante blu con barra animata
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
    );
  }
}
