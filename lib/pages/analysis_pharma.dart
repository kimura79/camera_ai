// 📄 lib/pages/analysis_pharma.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;
  final double score;
  final Map<String, double> indici;
  final List<String> consigli;
  final String tipoPelle;

  const AnalysisPharmaPage({
    super.key,
    required this.imagePath,
    required this.score,
    required this.indici,
    required this.consigli,
    required this.tipoPelle,
  });

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  bool _loading = false;
  String? _response;

  Future<void> _callAnalysisEndpoint() async {
    setState(() => _loading = true);

    try {
      final url = Uri.parse("https://tuo-server/analisi_pelle"); // 🔹 <-- metti qui il tuo endpoint
      final request = http.MultipartRequest('POST', url);

      request.files.add(await http.MultipartFile.fromPath('image', widget.imagePath));
      request.fields['tipo_pelle'] = widget.tipoPelle;

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() => _response = body);
      } else {
        setState(() => _response = "Errore: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _response = "Errore: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scorePercent = (widget.score * 100).clamp(0, 100);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text("Analisi della Pelle"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Immagine analizzata
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(widget.imagePath),
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 🔹 Titolo
            Center(
              child: Text(
                "Punteggio Complessivo",
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 🔹 Valore numerico grande
            Center(
              child: Text(
                "${scorePercent.toStringAsFixed(0)}%",
                style: GoogleFonts.montserrat(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A73E8),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 🔹 Barre degli indici
            Text(
              "Punteggi per ogni parametro (0–1)",
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            ...widget.indici.entries.map((entry) {
              final nome = entry.key;
              final valore = entry.value.clamp(0, 1.0).toDouble();
              final percent = (valore * 100).toStringAsFixed(0);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFCDE0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: valore,
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
                      "$percent%",
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

            // 🔹 Raccomandazioni
            Text(
              "Raccomandazioni Personalizzate",
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Formula skincare suggerita per te",
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                children: widget.consigli.map((txt) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "❗ ",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 18,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            txt,
                            style: GoogleFonts.montserrat(
                              fontSize: 15,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 40),

            // 🔹 Pulsante singolo “Analisi Pelle”
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  minimumSize: const Size(220, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _loading ? null : _callAnalysisEndpoint,
                child: _loading
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        "Analisi Pelle",
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),

            if (_response != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "📩 Risposta server: $_response",
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}