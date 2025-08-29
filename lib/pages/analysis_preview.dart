import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
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
  String? _overlayUrl;
  Uint8List? _overlayBytes;

  Future<void> _analyzeImage() async {
    setState(() {
      _loading = true;
      _result = null;
      _overlayUrl = null;
      _overlayBytes = null;
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
        final decoded = json.decode(body);
        setState(() {
          _result = decoded;
          if (decoded["overlay_url"] != null) {
            _overlayUrl = "http://46.101.223.88:5000${decoded["overlay_url"]}";
          }
        });

        // ✅ se esiste overlay, scaricalo e salvalo in galleria
        if (_overlayUrl != null) {
          final overlayResp = await http.get(Uri.parse(_overlayUrl!));
          if (overlayResp.statusCode == 200) {
            _overlayBytes = overlayResp.bodyBytes;

            final pState = await PhotoManager.requestPermissionExtend();
            if (pState.hasAccess) {
              await PhotoManager.editor.saveImage(
                _overlayBytes!,
                filename:
                    "overlay_${DateTime.now().millisecondsSinceEpoch}.png",
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("✅ Overlay salvato in galleria")),
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
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Anteprima"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // ✅ Immagine (o overlay se già calcolato) a schermo intero
          Expanded(
            child: Container(
              width: double.infinity,
              height: screenH * 0.8,
              color: Colors.black,
              child: _overlayBytes != null
                  ? Image.memory(_overlayBytes!, fit: BoxFit.contain)
                  : Image.file(File(widget.imagePath), fit: BoxFit.contain),
            ),
          ),

          const SizedBox(height: 12),

          // 🔘 Pulsante Analizza
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 52),
                backgroundColor: Colors.blue,
              ),
              onPressed: _loading ? null : _analyzeImage,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Analizza"),
            ),
          ),
        ],
      ),
    );
  }
}
