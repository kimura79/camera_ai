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
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://46.101.223.88:5000/analyze'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(body);
        setState(() {
          _result = data;
        });
      } else {
        throw Exception('Errore server: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore analisi: $e")),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Anteprima")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ✅ Mostra la foto esattamente 1024×1024
            AspectRatio(
              aspectRatio: 1,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain, // niente stretch
              ),
            ),
            const SizedBox(height: 20),

            if (_loading) const CircularProgressIndicator(),

            if (!_loading && _result == null)
              ElevatedButton(
                onPressed: _analyzeImage,
                child: const Text("Analizza"),
              ),

            if (_result != null) ...[
              const SizedBox(height: 20),
              Text("✅ Analisi completata"),
              if (_result!['percentuale'] != null)
                Text("Percentuale: ${_result!['percentuale']}%"),
              const SizedBox(height: 10),
              if (_result!['overlay_url'] != null)
                Image.network(
                  "http://46.101.223.88:5000${_result!['overlay_url']}",
                  height: 250,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
