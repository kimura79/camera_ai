// 📄 lib/pages/analysis_pharma.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;

  const AnalysisPharmaPage({super.key, required this.imagePath});

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  bool _loading = false;
  Map<String, double>? _indici;
  double? _scoreGenerale;
  String? _tipoPelle;
  List<String>? _consigli;

  // 🔹 URL del tuo server Flask
  final String serverUrl = "http://<IP_SERVER>:5005/analyze_farmacia"; // 🔧 aggiorna IP

  Future<void> _analyzeImage() async {
    setState(() => _loading = true);

    try {
      final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      request.files.add(await http.MultipartFile.fromPath('file', widget.imagePath));
      final response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);

        if (data["success"] == true) {
          setState(() {
            _indici = Map<String, double>.from(data["indici"]);
            _scoreGenerale = data["score_generale"];
            _tipoPelle = data["tipo_pelle"];
            _consigli = List<String>.from(data["consigli"]);
          });
        } else {
          _showError("Errore: ${data["error"]}");
        }
      } else {
        _showError("Errore server (${response.statusCode})");
      }
    } catch (e) {
      _showError("Errore di connessione: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _valutaGiudizio(double v) {
    if (v < 0.45) return "Scarso";
    if (v < 0.7) return "Sufficiente";
    return "Buono";
  }

  Color _coloreGiudizio(double v) {
    if (v < 0.45) return Colors.redAccent;
    if (v < 0.7) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text("Analisi della Pelle"),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)))
          : _indici == null
              ? _buildIntro()
              : _buildResults(),
    );
  }

  // =============================================================
  // 🔹 Intro con pulsante singolo
  // =============================================================
  Widget _buildIntro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.file(File(widget.imagePath), height: 240, fit: BoxFit.cover),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.analytics, color: Colors.white),
              label: Text(
                "Analizza Pelle",
                style: GoogleFonts.montserrat(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _analyzeImage,
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // 🔹 Risultati completi
  // =============================================================
  Widget _buildResults() {
    final indici = _indici!;
    final tipo = _tipoPelle ?? "Normale";
    final consigli = _consigli ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(widget.imagePath), height: 220, fit: BoxFit.cover),
          ),

          const SizedBox(height: 20),
          Text(
            "Punteggio Complessivo",
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "${((_scoreGenerale ?? 0) * 100).toStringAsFixed(0)}",
            style: GoogleFonts.montserrat(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A73E8),
            ),
          ),
          Text(
            "Salute della pelle",
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tipo,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE91E63),
              ),
            ),
          ),

          const SizedBox(height: 30),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Domini Cutanei",
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Valori per ogni dominio (0–1)",
            style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),

          ...indici.entries.map((entry) {
            final nome = entry.key;
            final valore = entry.value;
            final percentuale = (valore * 100).clamp(0, 100).toStringAsFixed(0);
            final giudizio = _valutaGiudizio(valore);
            final coloreGiudizio = _coloreGiudizio(valore);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        nome,
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        giudizio,
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: coloreGiudizio,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.pink.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: valore.clamp(0.0, 1.0),
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A73E8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$percentuale%",
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),

          const SizedBox(height: 40),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Raccomandazioni Personalizzate",
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Formula skincare suggerita per te",
            style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),

          _buildRefertiCard(consigli),

          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: const BorderSide(color: Color(0xFF1A73E8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Nuova Analisi",
                    style: GoogleFonts.montserrat(
                      color: const Color(0xFF1A73E8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Torna alla Home",
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // =============================================================
  // 🔹 Box referti
  // =============================================================
  Widget _buildRefertiCard(List<String> consigli) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: consigli.map((txt) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("❗ ",
                    style: TextStyle(color: Colors.redAccent, fontSize: 18)),
                Expanded(
                  child: Text(
                    txt,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}