import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:custom_camera_component/pages/analysis_pharma.dart';

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

  // 🔹 Controllo server
  Future<void> _checkServer() async {
    for (final url in _serverUrls) {
      try {
        final resp = await http.get(Uri.parse("$url/status")).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && jsonDecode(resp.body)["status"] == "ok") {
          setState(() {
            _serverReady = true;
            _activeServer = url;
          });
          return;
        }
      } catch (_) {}
    }
    _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
  }

  // 🔹 Invio immagine e analisi
  Future<void> _uploadAndAnalyze() async {
    if (!_serverReady || _activeServer.isEmpty) return;
    setState(() => _loading = true);

    try {
      // ✅ Copia immagine in percorso sicuro (evita "Bad file descriptor")
      final tmpDir = await getTemporaryDirectory();
      final safePath = "${tmpDir.path}/image_farmacia.jpg";
      await File(widget.imagePath).copy(safePath);

      debugPrint("📸 Percorso file inviato: $safePath");

      final uri = Uri.parse("$_activeServer/analyze_farmacia");
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', safePath));
      request.fields['mode'] = widget.mode;

      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final dir = await getTemporaryDirectory();

        // 📂 Salva JSON
        final jsonFile = File("${dir.path}/result_farmacia.json");
        await jsonFile.writeAsString(jsonEncode(jsonResp));

        // 📂 Scarica overlay PNG se presente
        if (jsonResp["overlay_url"] != null) {
          final overlayResp = await http.get(Uri.parse(jsonResp["overlay_url"]));
          final overlayFile = File("${dir.path}/overlay_farmacia.png");
          await overlayFile.writeAsBytes(overlayResp.bodyBytes);
          debugPrint("🖼️ Overlay scaricato: ${overlayFile.path}");
        }

        // 🔄 Passa alla pagina dei risultati
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AnalysisPharmaPage(imagePath: safePath),
            ),
          );
        }
      } else {
        throw Exception("Errore analisi: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Errore durante analisi: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Errore durante l’analisi: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 🔹 Pulsante gradient principale
  Widget _buildGradientButton(String label, {required VoidCallback onPressed, bool disabled = false}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: disabled
                ? [Colors.grey.shade400, Colors.grey.shade300]
                : const [Color(0xFF1A97F3), Color(0xFF38BDF8)],
          ),
        ),
        child: ElevatedButton(
          onPressed: disabled || _loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ),
    );
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
            ),
            const SizedBox(height: 24),
            _serverReady
                ? const Text("✅ Server connesso e pronto", style: TextStyle(color: Colors.green))
                : const Text("❌ Server non raggiungibile", style: TextStyle(color: Colors.red)),
            const SizedBox(height: 30),
            _buildGradientButton(
              _serverReady ? "Analizza Pelle" : "Attesa server...",
              onPressed: _uploadAndAnalyze,
              disabled: !_serverReady,
            ),
          ],
        ),
      ),
    );
  }
}