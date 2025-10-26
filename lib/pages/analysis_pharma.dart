import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalysisPharmaPage extends StatelessWidget {
  final String imagePath; // 👈 parametro obbligatorio
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
  Widget build(BuildContext context) {
    final double scorePercent = (score * 100).clamp(0, 100);
    final giudizioGlobale = _valutaGiudizio(score);

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

            // 🔹 Immagine analizzata
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath),
                height: 220,
                fit: BoxFit.cover,
              ),
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
              "${scorePercent.toStringAsFixed(0)}",
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

            // 🔹 Tipo pelle
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

            // === Radar Chart ===
            _buildRadarChart(indici),

            const SizedBox(height: 30),

            // === Cerchi giudizi sintetici ===
            _buildCerchiGiudizi(score),

            const SizedBox(height: 40),

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

            const SizedBox(height: 40),

            // === Referti / Consigli ===
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
      ),
    );
  }

  // =============================================================
  // 🟢 WIDGETS SECONDARI
  // =============================================================

  Widget _buildRadarChart(Map<String, double> indici) {
    final labels = indici.keys.toList();
    final values = indici.values.map((v) => v.toDouble()).toList();

    return SizedBox(
      height: 260,
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          tickCount: 4,
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          radarBorderData: const BorderSide(color: Color(0xFF1A73E8), width: 2),
          gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
          titleTextStyle: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),

          dataSets: [
            RadarDataSet(
              fillColor: const Color(0xFF1A73E8).withOpacity(0.3),
              borderColor: const Color(0xFF1A73E8),
              entryRadius: 3,
              borderWidth: 2,
              dataEntries: values.map((v) => RadarEntry(value: v.toDouble())).toList(),
            ),
          ],

          getTitle: (index, angle) {
            return RadarChartTitle(
              text: labels[index],
              positionPercentageOffset: 1.2,
              textStyle: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCerchiGiudizi(double score) {
    String giudizio = _valutaGiudizio(score);
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

  String _valutaGiudizio(double score) {
    if (score < 0.45) return "Scarso";
    if (score < 0.7) return "Sufficiente";
    return "Buono";
  }
}
