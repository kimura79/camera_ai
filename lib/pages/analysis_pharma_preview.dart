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

  // ✅ IP DEFINITIVO DEL SERVER FARMACIA
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

  // 🔹 Verifica server e tenta ogni 5s
  Future<void> _checkServer() async {
    try {
      final resp = await http
          .get(Uri.parse("$_serverBaseUrl/status"))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 &&
          jsonDecode(resp.body)["status"].toString().toLowerCase() == "ok") {
        setState(() => _serverReady = true);
      } else {
        _startRetry();
      }
    } catch (_) {
      _startRetry();
    }
  }

  void _startRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), _checkServer);
  }

  // 🔹 Invio immagine al server
  Future<void> _uploadAndAnalyze() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
          "$_serverBaseUrl/analyze_pharma/${widget.mode.toLowerCase()}");
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore durante l’analisi: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 🔹 Pulsante stile principale (gradient blu)
  Widget _buildGradientButton(String label,
      {required VoidCallback onPressed, bool disabled = false}) {
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: disabled || _loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Text(
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

  Widget _buildServerStatus() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _serverReady ? Icons.check_circle : Icons.error_outline,
            color: _serverReady ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _serverReady
                ? "Server connesso e pronto"
                : "Server non raggiungibile",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _serverReady ? Colors.green : Colors.red,
            ),
          ),
        ],
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
              child: Image.file(
                File(widget.imagePath),
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            _buildServerStatus(),
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