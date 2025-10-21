import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 💊 Analisi Farmacia – placeholder con stile Lovable
class AnalisiFarmaciaPage extends StatelessWidget {
  const AnalisiFarmaciaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final double scoreComplessivo = 0.88;
    final Map<String, double> scores = {
      "Idratazione": 0.88,
      "Texture": 0.93,
      "Chiarezza": 0.92,
      "Elasticità": 0.85,
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // HEADER BLU
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 70, bottom: 40),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A97F3), Color(0xFF38BDF8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Text(
                  "Analisi della Pelle",
                  style: GoogleFonts.montserrat(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Carica o scatta una foto per iniziare",
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // CARD punteggio complessivo
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text("✨ Punteggio Complessivo",
                            style: GoogleFonts.montserrat(
                                fontSize: 16,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 10),
                        Text(
                          (scoreComplessivo * 100).toStringAsFixed(0),
                          style: GoogleFonts.montserrat(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A97F3),
                          ),
                        ),
                        Text("Salute della pelle",
                            style: GoogleFonts.montserrat(
                                color: Colors.grey[600], fontSize: 14)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.pink[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Mista",
                            style: GoogleFonts.montserrat(
                                color: Colors.pink[800],
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // CARD Analisi dettagliata
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Analisi Dettagliata",
                            style: GoogleFonts.montserrat(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A97F3),
                            )),
                        const SizedBox(height: 8),
                        Text("Punteggi per ogni parametro (0–1)",
                            style: GoogleFonts.montserrat(
                                fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(height: 20),
                        for (var entry in scores.entries)
                          _buildBar(entry.key, entry.value),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Placeholder per raccomandazioni
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.recommend,
                                color: Colors.green, size: 24),
                            const SizedBox(width: 8),
                            Text("Raccomandazioni Personalizzate",
                                style: GoogleFonts.montserrat(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700])),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Formula skincare suggerita per te:",
                          style: GoogleFonts.montserrat(
                              fontSize: 14, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 12),
                        for (var s in [
                          "💧 Usa un siero con acido ialuronico per aumentare l'idratazione.",
                          "🌞 Applica una crema con vitamina C per migliorare la luminosità.",
                          "🧴 Utilizza un prodotto con retinolo per migliorare la texture.",
                          "🕶️ Non dimenticare la protezione solare SPF 50+ ogni giorno.",
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(s,
                                style: GoogleFonts.montserrat(
                                    fontSize: 13, color: Colors.grey[800])),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.montserrat(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              Text("${(value * 100).toStringAsFixed(0)}%",
                  style: GoogleFonts.montserrat(
                      fontSize: 13, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Container(
                height: 10,
                width: value * 300,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A97F3), Color(0xFFE573A4)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

