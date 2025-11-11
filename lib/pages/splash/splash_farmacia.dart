import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';

/// 💊 Splash Farmacia (sfondo bianco + pulsante Fotocamera con picker)
class SplashFarmacia extends StatelessWidget {
  const SplashFarmacia({super.key});

  void _showCameraPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Scegli modalità fotocamera",
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A97F3),
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 Opzione 1 — Analisi viso intero
              ListTile(
                leading: const Icon(Icons.face, color: Color(0xFF1A97F3), size: 28),
                title: Text(
                  "Analisi viso intero (Farmacia)",
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomePageWidget(),
                    ),
                  );
                },
              ),

              const Divider(),

              // 🔹 Opzione 2 — Analisi particolare (macro)
              ListTile(
                leading: const Icon(Icons.zoom_in, color: Color(0xFF38BDF8), size: 28),
                title: Text(
                  "Analisi particolare (macro)",
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomePageWidget(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ✅ Sfondo bianco puro
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔹 Logo Farmacia
              const Icon(
                Icons.local_pharmacy,
                color: Color(0xFF1A97F3),
                size: 90,
              ),
              const SizedBox(height: 30),

              // 🔹 Titolo su due righe
              Text(
                "Epidermys\nTest Farmacie",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  height: 1.2,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A97F3),
                ),
              ),
              const SizedBox(height: 10),

              Text(
                "Versione dedicata ai test in parafarmacia",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 60),

              // 🔹 Pulsante apri fotocamera
              SizedBox(
                width: double.infinity,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A97F3), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () => _showCameraPicker(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Apri Fotocamera",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 Info test
              Text(
                "Scatta la foto e ottieni i punteggi di analisi (0–1)",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
