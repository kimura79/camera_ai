import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 👤 Analisi Utente – placeholder con stile Lovable
class AnalisiUserPage extends StatelessWidget {
  const AnalisiUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    final double scoreComplessivo = 0.91;
    final Map<String, double> scores = {
      "Idratazione": 0.89,
      "Texture": 0.94,
      "Luminosità": 0.92,
      "Elasticità": 0.87,
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
                  "Scopri i tuoi indici di salute cutanea",
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
                        Text("Salute generale della pelle",
                            style: GoogleFonts.montserrat(
                                color: Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
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
                        for (var entry in scores.entries)
                          _buildBar(entry.key, entry.value),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A97F3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 60, vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Torna alla Home",
                      style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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

