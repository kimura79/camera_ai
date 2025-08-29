Hai detto:
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AnalysisPreview extends StatefulWidget {
  final String imagePath;

  const AnalysisPreview({super.key, required this.imagePath});

  @override
  State<AnalysisPreview> createState() => _AnalysisPreviewState();
}

class _AnalysisPreviewState extends State<AnalysisPreview> {
  bool _loading = false;
  Map<String, dynamic>? _result;

  Future<void> _analyzeImage() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/analyze"); // 🔗 tuo server
      final request = http.MultipartRequest("POST", uri);

      request.files.add(
        await http.MultipartFile.fromPath("file", widget.imagePath),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _result = json.decode(body);
        });
      } else {
        throw Exception("Errore server: ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Errore analisi: $e")),
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayUrl = _result != null && _result!["overlay_url"] != null
        ? "http://46.101.223.88:5000${_result!["overlay_url"]}"
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Anteprima"),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // ✅ Mostra foto scattata (crop 1024×1024) — più grande e centrata
            Container(
              width: MediaQuery.of(context).size.width * 0.9, // più largo
              height: MediaQuery.of(context).size.width * 0.9, // quadrato 1:1
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
              ),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover, // riempie tutto il quadrato
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _loading ? null : _analyzeImage,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Analizza"),
            ),

            const SizedBox(height: 24),

            // 📊 Risultato analisi
            if (_result != null) ...[
              const Text(
                "📊 Risultati:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  const JsonEncoder.withIndent("  ").convert(_result),
                  style: const TextStyle(fontFamily: "monospace"),
                ),
              ),

              const SizedBox(height: 20),

              // 🔥 Mostra overlay restituito dal server
              if (overlayUrl != null) ...[
                const Text(
                  "🖼️ Overlay:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.width * 0.9,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 3),
                  ),
                  child: Image.network(
                    overlayUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        const Center(child: Text("Errore caricamento overlay")),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
