import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;

  const AnalysisPharmaPage({super.key, required this.imagePath});

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  Map<String, dynamic>? resultData;

  @override
  void initState() {
    super.initState();
    _loadResultData();
  }

  Future<void> _loadResultData() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/result_farmacia.json");
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        setState(() => resultData = data);
      }
    } catch (e) {
      debugPrint("Errore caricamento JSON farmacia: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (resultData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
        ),
      );
    }

    final double score = (resultData!["score_generale"] ?? 0.0).toDouble();
    final Map<String, dynamic> indici =
        Map<String, dynamic>.from(resultData!["indici"] ?? {});
    final String tipoPelle = resultData!["tipo_pelle"] ?? "Normale";
    final List<String> consigli =
        List<String>.from(resultData!["consigli"] ?? []);

    final double scorePercent = (score * 100).clamp(0, 100);
    final giudizioGlobale = _valutaGiudizio(score);

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 📸 Immagine del volto
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath),
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),

            // 🔹 Score complessivo
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
              "${scorePercent.toStringAsFixed(0)}",
              style: GoogleFonts.montserrat(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A73E8),
              ),
            ),
            Text(
              giudizioGlobale,
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),

            // 🔹 Tipo di pelle
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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

            const SizedBox(height: 30),

            // 🔹 Cerchi di giudizio visivo
            _buildCerchiGiudizi(score),
            const SizedBox(height: 40),

            // 🔹 Domini cutanei
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
            ...indici.entries.map((entry) {
              final nome = entry.key;
              final valore = (entry.value as num).toDouble();
              final giudizio = _valutaGiudizio(valore);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$nome – $giudizio",
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
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: valore.toDouble(),
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

            const SizedBox(height: 40),

            // 🔹 Raccomandazioni
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
            _buildRefertiCard(consigli),

            const SizedBox(height: 30),
            ElevatedButton(
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // 🟢 WIDGETS SECONDARI
  // =============================================================

  Widget _buildCerchiGiudizi(double score) {
    final giudizio = _valutaGiudizio(score);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _cerchioGiudizio("Scarso", giudizio == "Scarso"),
        _cerchioGiudizio("Sufficiente", giudizio == "Sufficiente"),
        _cerchioGiudizio("Buono", giudizio == "Buono"),
      ],
    );
  }

  Widget _cerchioGiudizio(String label, bool attivo) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: attivo ? const Color(0xFF1A73E8) : Colors.grey.shade300,
          ),
          child: Center(
            child: Text(
              label.substring(0, 1),
              style: GoogleFonts.montserrat(
                color: attivo ? Colors.white : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            color: attivo ? const Color(0xFF1A73E8) : Colors.black54,
          ),
        ),
      ],
    );
  }

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
                        fontSize: 15, color: Colors.black87),
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