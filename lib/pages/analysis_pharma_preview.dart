import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:custom_camera_component/pages/analysis_pharma.dart';

/// ============================================================
/// 📸 ANALISI FARMACIA (versione asincrona con job polling)
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

class _AnalysisPharmaPreviewState extends State<AnalysisPharmaPreview> {
  bool _loading = false;
  bool _serverReady = false;
  bool _showServerStatus = true;
  Timer? _retryTimer;
  final List<String> _serverUrls = ["http://46.101.223.88:5005"];
  String _activeServer = "";

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // 🔹 Controlla che il server farmacia sia online
  // ============================================================
  Future<void> _checkServer() async {
    for (final url in _serverUrls) {
      try {
        final resp =
            await http.get(Uri.parse("$url/status")).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 &&
            jsonDecode(resp.body)["status"].toString().toLowerCase() == "ok") {
          setState(() {
            _serverReady = true;
            _activeServer = url;
            _showServerStatus = true;
          });
          // Nasconde il messaggio dopo 1 secondo
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() => _showServerStatus = false);
            }
          });
          return;
        }
      } catch (_) {}
    }
    setState(() {
      _serverReady = false;
      _showServerStatus = true;
    });
    // Nasconde il messaggio dopo 1 secondo anche in caso di errore
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _showServerStatus = false);
      }
    });
    _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
  }

  // ============================================================
  // 🔹 Invia immagine al server (nuovo endpoint asincrono)
  // ============================================================
  Future<void> _uploadAndAnalyze() async {
    if (!_serverReady || _activeServer.isEmpty) return;
    setState(() => _loading = true);

    try {
      // ✅ Nuovo endpoint asincrono
      final uri = Uri.parse("$_activeServer/upload_async/farmacia");
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final jobId = jsonResp["job_id"];
        if (jobId == null) throw Exception("job_id non ricevuto");
        await _pollJob(jobId);
      } else {
        throw Exception("Errore analisi: ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore durante l’analisi: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============================================================
  // 🔹 Polling periodico su /job/<id> senza limite di tempo
  // ============================================================
  Future<void> _pollJob(String jobId) async {
    final dir = await getTemporaryDirectory();
    const pollingInterval = Duration(seconds: 2);
    int attempts = 0;

    while (mounted) {
      await Future.delayed(pollingInterval);
      final url = Uri.parse("$_activeServer/job/$jobId");
      final resp = await http.get(url);

      if (resp.statusCode != 200) continue;

      final data = jsonDecode(resp.body);
      final status = data["status"];
      debugPrint("⏱️ Stato job $jobId: $status");

      if (status == "ready") {
        final result = data["result"];
        if (result == null) throw Exception("Risultato non trovato");

        // Salva JSON in locale
        final jsonFile = File("${dir.path}/result_farmacia.json");
        await jsonFile.writeAsString(jsonEncode(result));

        // Scarica overlay se presente
        if (result["overlay_url"] != null) {
          final overlayResp = await http.get(Uri.parse(result["overlay_url"]));
          final overlayFile = File("${dir.path}/overlay_farmacia.png");
          await overlayFile.writeAsBytes(overlayResp.bodyBytes);
          debugPrint("🖼️ Overlay salvato: ${overlayFile.path}");
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisPharmaPage(imagePath: widget.imagePath),
          ),
        );
        return;
      }

      if (status == "failed") {
        throw Exception(data["error"] ?? "Analisi fallita");
      }

      attempts++;
      if (attempts % 30 == 0) {
        debugPrint("⏳ Analisi ancora in corso (${attempts * 2} s)...");
      }
    }
  }

  // ============================================================
  // 🔹 UI
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

            // ✅ Mostra messaggio solo per 1 secondo, poi scompare
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

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _serverReady ? _uploadAndAnalyze : null,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Analizza Pelle",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}