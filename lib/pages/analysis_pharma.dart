// 📄 lib/pages/analysis_pharma.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;

  const AnalysisPharmaPage({
    super.key,
    required this.imagePath,
  });

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  bool _loading = false;
  Map<String, dynamic>? _result;

  // 🔹 URL del server farmacie (aggiorna con il tuo dominio reale)
  final String apiUrl = "https://tuo-server.it/analyze_farmacie";

  Future<void> _analizzaPelle() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final uri = Uri.parse(apiUrl);
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath('image', widget.imagePath));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(respStr);
        setState(() => _result = data);
      } else {
        setState(() => _result = {
              "errore": "Errore server ${response.statusCode}",
              "dettagli": respStr,
            });
      }
    } catch (e) {
      setState(() => _result = {"errore": e.toString()});
    } finally {
      setState(() => _loading = false);
    }
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
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 10),

            // 🔹 Immagine
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath),
                height: 240,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 30),

            // 🔹 Pulsante unico
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _loading ? null : _analizzaPelle,
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
                      "Analizza Pelle",
                      style: GoogleFonts.montserrat(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),

            const SizedBox(height: 40),

            if (_result != null)
              _result!.containsKey("errore")
                  ? _buildErrorBox(_result!)
                  : _buildResultBox(_result!),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // 🔴 BOX ERRORE
  // ===========================================================
  Widget _buildErrorBox(Map<String, dynamic> err) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "❌ Errore: ${err["errore"]}\n${err["dettagli"] ?? ""}",
        style: GoogleFonts.montserrat(color: Colors.red.shade700),
      ),
    );
  }

  // ===========================================================
  // 🟢 BOX RISULTATO
  // ===========================================================
  Widget _buildResultBox(Map<String, dynamic> data) {
    final double? score = (data["score"] is num) ? data["score"].toDouble() : null;
    final Map<String, dynamic> indici = (data["indici"] ?? {}).cast<String, dynamic>();
    final tipoPelle = data["tipo_pelle"] ?? "—";
    final consigli = (data["consigli"] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titolo
        Text(
          "Risultato Analisi",
          style: GoogleFonts.montserrat(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),

        // 🔹 Punteggio complessivo
        if (score != null)
          Center(
            child: Column(
              children: [
                Text(
                  "${(score * 100).toStringAsFixed(0)}",
                  style: GoogleFonts.montserrat(
                    fontSize: 68,
                    color: const Color(0xFF1A73E8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Salute complessiva della pelle",
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 30),

        // 🔹 Tipo di pelle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tipoPelle,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE91E63),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // 🔹 Indici singoli
        if (indici.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: indici.entries.map((entry) {
              final nome = entry.key;
              final valore =
                  (entry.value is num) ? (entry.value as num).clamp(0, 1).toDouble() : 0.0;
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
                      ),
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
                      "${(valore * 100).toStringAsFixed(0)}%",
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
          ),

        const SizedBox(height: 40),

        // 🔹 Consigli personalizzati
        Text(
          "Raccomandazioni Personalizzate",
          style: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        ...consigli.map((c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "• $c",
                style: GoogleFonts.montserrat(fontSize: 15, color: Colors.black87),
              ),
            )),
      ],
    );
  }
}