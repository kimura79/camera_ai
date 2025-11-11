import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';


/// 💊 Splash Farmacia (sfondo bianco + pulsante Fotocamera)
class SplashFarmacia extends StatelessWidget {
  const SplashFarmacia({super.key});

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
              // 🔹 Logo Farmacia o icona
              const Icon(
                Icons.local_pharmacy,
                color: Color(0xFF1A97F3),
                size: 90,
              ),
              const SizedBox(height: 30),

              // 🔹 Titolo
              Text(
                "Epidermys – Test Farmacie",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 24,
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

// 🔹 Pulsante apri fotocamera / galleria / file
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
      onPressed: () async {
        final ImagePicker picker = ImagePicker();

        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            return SafeArea(
              child: Wrap(
                children: [
                  // 🔹 1️⃣ Fotocamera interna dell’app
                  ListTile(
                    leading:
                        const Icon(Icons.camera_alt, color: Color(0xFF1A97F3)),
                    title: const Text("Fotocamera (App Epidermys)"),
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

                  // 🔹 2️⃣ Galleria
                  ListTile(
                    leading: const Icon(Icons.photo_library,
                        color: Color(0xFF38BDF8)),
                    title: const Text("Galleria"),
                    onTap: () async {
                      Navigator.pop(context);
                      final XFile? image =
                          await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        // Qui apri la stessa schermata fotocamera, simulando scatto
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HomePageWidget(),
                          ),
                        );
                      }
                    },
                  ),

                  // 🔹 3️⃣ File
                  ListTile(
                    leading:
                        const Icon(Icons.folder, color: Color(0xFF60A5FA)),
                    title: const Text("File"),
                    onTap: () async {
                      Navigator.pop(context);
                      final XFile? file =
                          await picker.pickImage(source: ImageSource.gallery);
                      if (file != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HomePageWidget(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
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
        "Apri Fotocamera / Galleria / File",
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
