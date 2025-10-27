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
  const AnalysisPharmaPreview({super.key, required this.imagePath, this.mode = "fullface"});
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

  Future<void> _uploadAndAnalyze() async {
    if (!_serverReady || _activeServer.isEmpty) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse("$_activeServer/upload_async/farmacia");
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));
      final resp = await req.send();
      final respStr = await resp.stream.bytesToString();
      if (resp.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final jobId = jsonResp["job_id"];
        await _pollJob(jobId);
      } else {
        throw Exception("Errore analisi ${resp.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pollJob(String jobId) async {
    final dir = await getTemporaryDirectory();
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final resp = await http.get(Uri.parse("$_activeServer/job/$jobId"));
      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body);
      if (data["status"] == "ready") {
        final result = data["result"];
        await File("${dir.path}/result_farmacia.json").writeAsString(jsonEncode(result));
        if (result["overlay_url"] != null) {
          final oResp = await http.get(Uri.parse(result["overlay_url"]));
          await File("${dir.path}/overlay_farmacia.png").writeAsBytes(oResp.bodyBytes);
        }
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AnalysisPharmaPage(imagePath: widget.imagePath)),
          );
        }
        return;
      } else if (data["status"] == "failed") {
        throw Exception(data["error"] ?? "Analisi fallita");
      }
    }
    throw Exception("Timeout analisi");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(backgroundColor: const Color(0xFF1A73E8), title: const Text("Analisi Farmacia")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
          ),
          const SizedBox(height: 24),
          _serverReady
              ? const Text("✅ Server connesso", style: TextStyle(color: Colors.green))
              : const Text("❌ Server offline", style: TextStyle(color: Colors.red)),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _serverReady ? _uploadAndAnalyze : null,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("Analizza Pelle", style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ]),
      ),
    );
  }
}
