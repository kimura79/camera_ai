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
  final String serverUrl = "https://pacific-water-thumbzilla-ventures.trycloudflare.com";
  String _activeServer = "";

  // 🔹 per la barra di avanzamento
  double _progress = 0.0;
  String _statusMessage = "Analisi in corso...";

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

@override
void dispose() {
  _retryTimer?.cancel();
  _cancelAllJobs(); // 🧹 cancella job anche se l’utente chiude la pagina
  super.dispose();
}


// ============================================================
// 🔹 Controlla che il server farmacia sia online 
// ============================================================
Future<void> _checkServer() async {
  const serverUrl = "https://pacific-water-thumbzilla-ventures.trycloudflare.com"; // ✅ Cloudflare Tunnel

  try {
    final resp = await http
        .get(Uri.parse("$serverUrl/status"))
        .timeout(const Duration(seconds: 4));

    if (resp.statusCode == 200 &&
        jsonDecode(resp.body)["status"].toString().toLowerCase() == "ok") {
      setState(() {
        _serverReady = true;
        _activeServer = serverUrl;
        _showServerStatus = true;
      });

      debugPrint("✅ Server online: $serverUrl");

      // Nasconde messaggio dopo 1s
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showServerStatus = false);
      });
      return;
    } else {
      debugPrint("⚠️ Server risponde ma non OK: ${resp.statusCode}");
    }
  } catch (e) {
    debugPrint("❌ Server non raggiungibile: $e");
  }

  // Se non ha risposto correttamente
  setState(() {
    _serverReady = false;
    _showServerStatus = true;
  });

  debugPrint("🚨 Server offline, nuovo tentativo tra 5s...");

  Future.delayed(const Duration(seconds: 1), () {
    if (mounted) setState(() => _showServerStatus = false);
  });

  // Ritenta dopo 5 secondi
  _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
}

// ============================================================
// 🔹 Invia immagine al server (endpoint asincrono con retry)
// ============================================================
Future<void> _uploadAndAnalyze() async {
  // Verifica che il server sia pronto
  if (!_serverReady || _activeServer.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⚠️ Server non pronto. Riprova tra pochi secondi."),
      ),
    );
    return;
  }

  setState(() {
    _loading = true;
    _progress = 0.05;
  });

  try {
    final uri = Uri.parse("$_activeServer/upload_async/farmacia");
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', widget.imagePath));

    debugPrint("📤 Invio immagine al server: $_activeServer");

    final response = await request.send();
    final respStr = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final jsonResp = jsonDecode(respStr);
      final jobId = jsonResp["job_id"];
      if (jobId == null) throw Exception("job_id non ricevuto dal server");

      debugPrint("🚀 Job inviato con ID: $jobId");
      await _pollJob(jobId);
    } else {
      throw Exception("Errore server (${response.statusCode}): $respStr");
    }
  } catch (e) {
    debugPrint("❌ Errore durante l’analisi farmacia: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Errore durante l’analisi: $e"),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } finally {
    // ✅ Ripristina sempre lo stato per consentire retry
    if (mounted) {
      setState(() {
        _loading = false;
        _progress = 0.0;
        _serverReady = true; // abilita di nuovo il tasto Analizza
      });
    }
  }
}



  // ============================================================
// 🔹 Polling robusto e continuo su /job/<id> (fino a 10 minuti)
//    con messaggi di stato dinamici e barra fluida
// ============================================================
Future<void> _pollJob(String jobId) async {
  final dir = await getTemporaryDirectory();
  const pollingInterval = Duration(seconds: 3);
  const maxAttempts = 200; // ≈10 minuti
  int attempt = 0;

  while (attempt < maxAttempts && mounted) {
    attempt++;

    try {
      final url = Uri.parse("$_activeServer/job/$jobId");
      final resp = await http.get(url).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final status = data["status"] ?? "";
        final progress = (data["progress"] ?? 0).toDouble();
        final message = (data["message"] ?? "").toString();

        // 🔹 Aggiorna barra e messaggio visivo
        setState(() {
          _progress = progress / 100;
          _statusMessage = message.isNotEmpty ? message : "Analisi in corso...";
        });

        debugPrint("⏱️ Stato job $jobId: $status — $_statusMessage ($_progress)");

        // ✅ Job completato con risultato
        if ((status == "done" || status == "ready") && data["result"] != null) {
          final result = data["result"];
          setState(() {
            _progress = 1.0;
            _statusMessage = "Analisi completata ✅";
          });

          await Future.delayed(const Duration(milliseconds: 800));

          // Salva JSON risultato
          final jsonFile = File("${dir.path}/result_farmacia.json");
          await jsonFile.writeAsString(jsonEncode(result));

          // Salva overlay se presente
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
              builder: (_) => AnalysisPharmaPage(
                imagePath: widget.imagePath,
                jobId: jobId,
              ),
            ),
          );
          return;
        }

        // ❌ Job fallito
        if (status == "failed") {
          final errMsg = data["message"] ?? "Analisi fallita";
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("❌ Errore: $errMsg"),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          setState(() => _loading = false);
          return;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Errore polling: $e");
    }

    await Future.delayed(pollingInterval);
  }

  // ⏰ Timeout totale (dopo 10 minuti)
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⏰ Timeout: analisi non completata entro 10 minuti."),
        backgroundColor: Colors.redAccent,
      ),
    );
    setState(() {
      _loading = false;
      _statusMessage = "Timeout scaduto — riprova l’analisi";
    });
  }
}

// ============================================================
// 🧹 CANCELLA TUTTI I JOB ATTIVI (coerente con server_farmacie16.py)
// ============================================================
Future<void> _cancelAllJobs() async {
  try {
    final resp = await http.post(
      Uri.parse("$serverUrl/cancel_all_jobs"),
    ).timeout(const Duration(seconds: 6));

    if (resp.statusCode == 200) {
      debugPrint("🧹 Tutti i job cancellati lato server: ${resp.body}");
    } else {
      debugPrint("⚠️ Errore cancellazione job (${resp.statusCode}): ${resp.body}");
    }
  } catch (e) {
    debugPrint("❌ Errore cancel_all_jobs: $e");
  }
}


  // ============================================================
  // 🔹 UI — con gestione back e cancellazione job
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _cancelAllJobs(); // 🧹 Cancella tutti i job quando si torna indietro
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
              await _cancelAllJobs(); // 🧹 Cancella anche dal pulsante back
              if (mounted) Navigator.of(context).pop();
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

              // ✅ Mostra messaggio solo per 1 secondo, poi scompare
              if (_showServerStatus)
                (_serverReady
                    ? const Text(
                        "✅ Server connesso e pronto",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const Text(
                        "❌ Server non raggiungibile",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      )),

              const SizedBox(height: 10),

              // ============================================================
              // 🔹 PULSANTE / BARRA AVANZAMENTO
              // ============================================================
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
                          width:
                              MediaQuery.of(context).size.width * _progress,
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
