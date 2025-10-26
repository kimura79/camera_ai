import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
  Timer? _retryTimer;

  // 🔹 aggiorna se cambi porta o dominio
  final String _serverBaseUrl = "http://46.101.223.88:5005";

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

  Future<void> _checkServer() async {
    try {
      final resp = await http
          .get(Uri.parse("$_serverBaseUrl/status"))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && jsonDecode(resp.body)["status"] == "ok") {
        setState(() => _serverReady = true);
      } else {
        _startRetry();
      }
    } catch (_) {
      _startRetry();
    }
  }

  void _startRetry() {
    if (_serverReady) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
  }

  Future<void> _uploadAndAnalyze() async {
    setState(() => _loading = true);
    try {
      final tipo = widget.mode;
      final uri = Uri.parse("$_serverBaseUrl/analyze_pharma/$tipo");
      final request = http.MultipartRequest('POST', uri);
      request.files
          .add(await http.MultipartFile.fromPath('image', widget.imagePath));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(respStr);
        final dir = await getTemporaryDirectory();
        final file = File("${dir.path}/result_farmacia.json");
        await file.writeAsString(jsonEncode(jsonResp));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AnalysisPharmaPage(imagePath: widget.imagePath),
            ),
          );
        }
      } else {
        throw Exception("Errore analisi: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Errore analisi: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Errore durante l’analisi: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildGradientButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 60,
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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

  Widget _buildServerError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Text(
                "Server non raggiungibile",
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildGradientButton("Riprova connessione", _checkServer),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: _buildGradientButton("Analizza Pelle", _uploadAndAnalyze),
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
      body: Column(
        children: [
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(widget.imagePath),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 20),
          if (!_serverReady) _buildServerError(),
          if (_serverReady) _buildAnalyzeButton(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
            ),
        ],
      ),
    );
  }
}