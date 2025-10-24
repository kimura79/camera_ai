// 📄 lib/pages/analysis_pharma_preview.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    try {
      final resp = await http
          .get(Uri.parse("http://46.101.223.88:5000/status"))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        setState(() => _serverReady = true);
      } else {
        setState(() => _serverReady = false);
      }
    } catch (_) {
      setState(() => _serverReady = false);
    }
  }

  Future<String> _copyToSafePath(String originalPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final safePath =
        "${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg";
    await File(originalPath).copy(safePath);
    return safePath;
  }

  Future<Map<String, dynamic>> _waitForResult(String jobId) async {
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

  Future<void> _callAnalysisAsync(String tipo) async {
    setState(() => _loading = true);
    try {
      final safePath = await _copyToSafePath(widget.imagePath);
      final uri = Uri.parse("http://46.101.223.88:5000/upload_async/$tipo");

      final req = http.MultipartRequest("POST", uri);
      req.files.add(await http.MultipartFile.fromPath("file", safePath));
      req.fields["mode"] = widget.mode;

      final resp = await req.send();
      final body = await resp.stream.bytesToString();
      final decoded = jsonDecode(body);
      final String jobId = decoded["job_id"];

      final result = await _waitForResult(jobId);

      if (!mounted) return;

      // ✅ Mostra direttamente la pagina score
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisPharmaPage(
            imagePath: widget.imagePath, // ✅ parametro obbligatorio
            score: (result["percentuale"] ?? 0).toDouble(),
            indici: {
              "Idratazione": 0.84,
              "Texture": 0.88,
              "Chiarezza": 0.82,
              "Elasticità": 0.80,
            },
            consigli: [
              "Applica una crema idratante giorno e notte.",
              "Usa siero alla vitamina C per migliorare la luminosità.",
              "Applica sempre protezione solare SPF 50+.",
              "Considera booster con niacinamide per uniformare il tono.",
            ],
            tipoPelle: "Normale",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Errore: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 🔹 Pulsante gradiente arrotondato (stile main.dart)
  Widget _buildGradientButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: 150,
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
              fontSize: 16,
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
      appBar: AppBar(
        title: const Text("Analisi Farmacia"),
        backgroundColor: const Color(0xFF1A73E8),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Image.file(File(widget.imagePath)),
                const SizedBox(height: 24),
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
                  Column(
                    children: [
                      const Text(
                        "Seleziona il tipo di analisi da eseguire:",
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),

                      // 🔹 Pulsanti in griglia 2x2, stile gradient
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildGradientButton(
                              "Rughe", () => _callAnalysisAsync("rughe")),
                          _buildGradientButton(
                              "Macchie", () => _callAnalysisAsync("macchie")),
                          _buildGradientButton(
                              "Melasma", () => _callAnalysisAsync("melasma")),
                          _buildGradientButton(
                              "Pori", () => _callAnalysisAsync("pori")),
                        ],
                      ),
                    ],
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
    );
  }
}