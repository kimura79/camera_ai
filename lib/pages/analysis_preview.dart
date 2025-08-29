import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'dart:convert';
import 'dart:typed_data';

class AnalysisPreview extends StatefulWidget {
  final String imagePath;

  const AnalysisPreview({super.key, required this.imagePath});

  @override
  State<AnalysisPreview> createState() => _AnalysisPreviewState();
}

class _AnalysisPreviewState extends State<AnalysisPreview> {
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _savedOverlayPath;

  Future<void> _analyzeImage() async {
    setState(() {
      _loading = true;
      _result = null;
      _savedOverlayPath = null;
    });

    try {
      final uri = Uri.parse("http://46.101.223.88:5000/analyze");
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
        });

        // ✅ scarica overlay e salva in galleria
        if (decoded["overlay_url"] != null) {
          final overlayUrl = "http://46.101.223.88:5000${decoded["overlay_url"]}";
          await _downloadAndSaveOverlay(overlayUrl);
        }
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

  Future<void> _downloadAndSaveOverlay(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;

        final PermissionState pState =
            await PhotoManager.requestPermissionExtend();
        if (!pState.hasAccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permesso Foto negato')),
          );
          return;
        }

        final filename = "overlay_${DateTime.now().millisecondsSinceEpoch}.png";
        final asset = await PhotoManager.editor.saveImage(
          bytes,
          filename: filename,
        );

        if (asset != null) {
          final tempDir = await Directory.systemTemp.createTemp("epi_overlay");
          final filePath = "${tempDir.path}/$filename";
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          setState(() {
            _savedOverlayPath = filePath;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Overlay salvato in galleria")),
          );
        }
      }
    } catch (e) {
      debugPrint("Errore salvataggio overlay: $e");
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

            // ✅ Foto 1024x1024
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

            // ✅ Mostra overlay restituito
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
        ),
      ),
    );
  }
}
