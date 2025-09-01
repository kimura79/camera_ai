import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;

class AnalysisPreview extends StatefulWidget {
  final String imagePath;

  const AnalysisPreview({super.key, required this.imagePath});

  @override
  State<AnalysisPreview> createState() => _AnalysisPreviewState();
}

class _AnalysisPreviewState extends State<AnalysisPreview> {
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _overlayUrl;
  double? _percentuale;

  Future<void> _analyzeImage() async {
    setState(() {
      _loading = true;
      _result = null;
      _overlayUrl = null;
      _percentuale = null;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/analyze"); // 🔗 server
      final request = http.MultipartRequest("POST", uri);

      request.files.add(
        await http.MultipartFile.fromPath("file", widget.imagePath),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final decoded = json.decode(body);
        setState(() {
          _result = decoded;
          _overlayUrl = decoded["overlay_url"] != null
              ? "http://46.101.223.88:5000${decoded["overlay_url"]}"
              : null;
          _percentuale = decoded["percentuale"] != null
              ? (decoded["percentuale"] as num).toDouble()
              : null;
        });

        // 🔐 Se arriva overlay → salvalo in galleria
        if (_overlayUrl != null) {
          final overlayResp = await http.get(Uri.parse(_overlayUrl!));
          if (overlayResp.statusCode == 200) {
            final bytes = overlayResp.bodyBytes;
            final PermissionState pState =
                await PhotoManager.requestPermissionExtend();
            if (pState.isAuth) {
              await PhotoManager.editor.saveImage(
                bytes,
                filename:
                    "overlay_${DateTime.now().millisecondsSinceEpoch}.png",
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Overlay salvato in galleria")),
                );
              }
            }
          }
        }
      } else {
        throw Exception("Errore server: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore analisi: $e")),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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

            // ✅ Foto originale
            Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
              ),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
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
            if (_overlayUrl != null) ...[
              const Text(
                "🔬 Analisi Macchie",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Overlay
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.width * 0.9,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 3),
                ),
                child: Image.network(
                  _overlayUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) =>
                      const Center(child: Text("Errore caricamento overlay")),
                ),
              ),

              const SizedBox(height: 20),

              // 📊 Percentuale + barra
              if (_percentuale != null) ...[
                Text(
                  "Percentuale macchie: ${_percentuale!.toStringAsFixed(2)}%",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_percentuale! / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  minHeight: 12,
                ),
              ],

              const SizedBox(height: 30),

              // 🆕 Giudizio medico
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
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Hai dato voto $voto"),
                        ),
                      );
                      // 🔗 qui collegheremo upload voto → server
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
