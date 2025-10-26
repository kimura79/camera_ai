// 📄 lib/pages/analysis_pharma_preview.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:custom_camera_component/pages/analysis_pharma.dart';

class AnalysisPharmaPreview extends StatefulWidget {
  final String imagePath;
  final String mode; // "fullface" o "particolare"

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

  final String serverBase = "http://46.101.223.88:5005"; // 🔧 IP server farmacie

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  // 🔹 Verifica connessione con server Flask
  Future<void> _checkServer() async {
    try {
      final resp =
          await http.get(Uri.parse("$serverBase/status")).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        setState(() => _serverReady = true);
      } else {
        setState(() => _serverReady = false);
      }
    } catch (_) {
      setState(() => _serverReady = false);
    }
  }

  // 🔹 Copia sicura immagine in documenti app
  Future<String> _copyToSafePath(String originalPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final safePath = "${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg";
    await File(originalPath).copy(safePath);
    return safePath;
  }

  // 🔹 Chiamata all’unico endpoint /analyze_farmacia
  Future<void> _callFarmaciaAnalysis() async {
    setState(() => _loading = true);

    try {
      final safePath = await _copyToSafePath(widget.imagePath);
      final uri = Uri.parse("$serverBase/analyze_farmacia");

      final req = http.MultipartRequest("POST", uri);
      req.files.add(await http.MultipartFile.fromPath("file", safePath));

      final resp = await req.send();
      final body = await resp.stream.bytesToString();
      final data = jsonDecode(body);

      if (resp.statusCode == 200 && data["success"] == true) {
        // Salva JSON temporaneo per la pagina successiva
        final dir = await getTemporaryDirectory();
        final resultFile = File("${dir.path}/result_farmacia.json");
        await resultFile.writeAsString(jsonEncode(data));

        if (!mounted) return;

        // ✅ Vai alla pagina risultati
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisPharmaPage(
              imagePath: widget.imagePath,
            ),
          ),
        );
      } else {
        _showError("Errore analisi: ${data["error"] ?? "Risposta non valida"}");
      }
    } catch (e) {
      _showError("Errore di connessione: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 🔹 Pulsante principale “Analizza Pelle”
  Widget _buildGradientButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A97F3), Color(0xFF38BDF8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        title: const Text("Analisi Farmacia"),
        backgroundColor: const Color(0xFF1A73E8),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
                ),
                const SizedBox(height: 40),
                if (!_serverReady)
                  Column(
                    children: [
                      const Text("🔴 Server non raggiungibile"),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _checkServer,
                        child: const Text("Riprova connessione"),
                      ),
                    ],
                  )
                else
                  _buildGradientButton("Analizza Pelle", _callFarmaciaAnalysis),
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