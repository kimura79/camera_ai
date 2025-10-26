// 📄 lib/pages/analysis_pharma.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;
  final double? score;
  final Map<String, double>? indici;
  final List<String>? consigli;
  final String? tipoPelle;

  const AnalysisPharmaPage({
    super.key,
    required this.imagePath,
    this.score,
    this.indici,
    this.consigli,
    this.tipoPelle,
  });

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  bool _loading = false;
  double? score;
  Map<String, double>? indici;
  List<String>? consigli;
  String? tipoPelle;

  final String apiUrl = "http://localhost:5005/analyze_farmacia"; // 🔹 aggiorna con dominio reale

  @override
  void initState() {
    super.initState();
    score = widget.score;
    indici = widget.indici;
    consigli = widget.consigli;
    tipoPelle = widget.tipoPelle;
  }

  // ======================================================
  // 🔹 Invio immagine al server Flask
  // ======================================================
  Future<void> _analizzaPelle() async {
    setState(() => _loading = true);

    try {
      final request = http.MultipartRequest("POST", Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath("file", widget.imagePath));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

        if (data["success"] == true) {
          setState(() {
            score = (data["score_generale"] ?? 0).toDouble();
            tipoPelle = data["tipo_pelle"] ?? "-";
            consigli = (data["consigli"] as List?)?.cast<String>() ?? [];
            indici = (data["indici"] as Map?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble()));
          });
        } else {
          _showError("Errore: ${data["error"] ?? "Risposta non valida"}");
        }
      } else {
        _showError("Errore server: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Errore di rete: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white))),
    );
  }

  // ======================================================
  // 🔹 Costruzione interfaccia
  // ======================================================
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
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath),
                height: 240,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 30),

            // 🔹 Pulsante Analizza Pelle
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

            if (score != null && indici != null) _buildResultsSection(),
          ],
        ),
      ),
    );
  }

  // ======================================================
  // 🔹 Risultati e visualizzazione
  // ======================================================
  Widget _buildResultsSection() {
    final giudizio = _valutaGiudizio(score!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "Punteggio Complessivo",
          style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          "${(score! * 100).toStringAsFixed(0)}",
          style: GoogleFonts.montserrat(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A73E8),
          ),
        ),
        Text(
          giudizio,
          style: GoogleFonts.montserrat(
            fontSize: 18,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 20),

        if (tipoPelle != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tipoPelle!,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE91E63),
              ),
            ),
          ),

        const SizedBox(height: 30),

        // 🔹 Indici
        ...indici!.entries.map((e) => _buildIndice(e.key, e.value)),

        const SizedBox(height: 40),

        // 🔹 Consigli personalizzati
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Raccomandazioni Personalizzate",
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildRefertiCard(consigli ?? []),
      ],
    );
  }

  Widget _buildIndice(String nome, double valore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
  }

  Widget _buildRefertiCard(List<String> consigli) {
    if (consigli.isEmpty) {
      return Text(
        "Nessun consiglio disponibile.",
        style: GoogleFonts.montserrat(color: Colors.black54),
      );
    }

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
                const Text("• ", style: TextStyle(fontSize: 18)),
                Expanded(
                  child: Text(
                    txt,
                    style: GoogleFonts.montserrat(fontSize: 15),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _valutaGiudizio(double score) {
    if (score < 0.45) return "Scarso";
    if (score < 0.7) return "Sufficiente";
    return "Buono";
  }
}