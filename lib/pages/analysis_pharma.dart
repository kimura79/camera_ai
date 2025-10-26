// 📄 lib/pages/analysis_pharma_preview.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'analysis_pharma.dart';

class AnalysisPharmaPreview extends StatefulWidget {
  final String imagePath;

  const AnalysisPharmaPreview({super.key, required this.imagePath});

  @override
  State<AnalysisPharmaPreview> createState() => _AnalysisPharmaPreviewState();
}

class _AnalysisPharmaPreviewState extends State<AnalysisPharmaPreview> {
  bool _loading = false;
  bool _serverReady = false;

  final String serverUrl = "http://<IP_SERVER>:5005/status"; // 🔧 aggiorna IP del tuo server

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  // 🔹 Verifica se il server è raggiungibile
  Future<void> _checkServer() async {
    try {
      final resp = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        setState(() => _serverReady = true);
      } else {
        setState(() => _serverReady = false);
      }
    } catch (_) {
      setState(() => _serverReady = false);
    }
  }

  // 🔹 Esegue la chiamata all’endpoint Flask
  Future<void> _analyzeImage() async {
    if (!_serverReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Server non disponibile")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uri = Uri.parse("http://<IP_SERVER>:5005/analyze_farmacia"); // 🔧 aggiorna IP
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);

      if (response.statusCode == 200 && data["success"] == true) {
        // Salva risultato in file temporaneo (opzionale)
        final dir = await getTemporaryDirectory();
        final resultFile = File("${dir.path}/result_farmacia.json");
        await resultFile.writeAsString(jsonEncode(data));

        // Vai alla pagina risultati
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AnalysisPharmaPage(
                imagePath: widget.imagePath,
              ),
            ),
          );
        }
      } else {
        _showError("Errore nell'elaborazione dell'immagine");
      }
    } catch (e) {
      _showError("Errore di connessione: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text("Analisi Farmacia"),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(widget.imagePath),
                  height: 260,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 40),
              if (_loading)
                const CircularProgressIndicator(color: Color(0xFF1A73E8))
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.analytics, color: Colors.white),
                  label: Text(
                    "Analizza Pelle",
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _serverReady ? _analyzeImage : null,
                ),
              const SizedBox(height: 20),
              Text(
                _serverReady
                    ? "Server pronto per l’analisi"
                    : "Connessione al server in corso...",
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: _serverReady ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}