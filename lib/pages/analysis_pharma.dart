// 📄 lib/pages/analysis_pharma.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnalysisPharmaPage extends StatelessWidget {
  final double score;
  final Map<String, double> indici;
  final List<String> consigli;
  final String tipoPelle;

  const AnalysisPharmaPage({
    super.key,
    this.score = 82,
    this.indici = const {
      "Idratazione": 0.82,
      "Texture": 0.90,
      "Chiarezza": 0.82,
      "Elasticità": 0.81,
    },
    this.consigli = const [
      "Usa un siero con acido ialuronico per aumentare l’idratazione",
      "Applica una crema con vitamina C per migliorare la luminosità",
      "Utilizza un prodotto con retinolo per migliorare la texture",
      "Non dimenticare la protezione solare SPF 50+ ogni giorno",
      "Considera l’uso di niacinamide per uniformare il tono della pelle",
    ],
    this.tipoPelle = "Grassa",
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text("Analisi della Pelle"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
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
              score.toStringAsFixed(0),
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
                tipoPelle,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE91E63),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // === Analisi Dettagliata ===
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Analisi Dettagliata",
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Punteggi per ogni parametro (0–1)",
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            // === Barre degli indici ===
            ...indici.entries.map((entry) {
              final String nome = entry.key;
              final double valore = entry.value;
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

            const SizedBox(height: 30),

            // === Raccomandazioni Personalizzate ===
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
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            Container(
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
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 18)),
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
            ),

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
      ),
    );
  }
}
