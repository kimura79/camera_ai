import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';

/// 👤 Splash Utente Privato (stile Lovable con pulsante fotocamera)
class SplashUser extends StatelessWidget {
  const SplashUser({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE9F6FF), Color(0xFFCDEBFA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔹 Icona utente
                const Icon(Icons.face_retouching_natural,
                    color: Color(0xFF1A97F3), size: 90),
                const SizedBox(height: 30),

                // 🔹 Titolo
                Text(
                  "Epidermys AI",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A97F3),
                  ),
                ),
                const SizedBox(height: 10),

                // 🔹 Sottotitolo
                Text(
                  "Analisi intelligente per la cura della pelle",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 60),

                // 🔹 Pulsante fotocamera
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
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HomePageWidget(),
                          ),
                        );
                      },
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
                  "Scatta una foto del tuo volto per avviare l’analisi",
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
      ),
    );
  }
}
