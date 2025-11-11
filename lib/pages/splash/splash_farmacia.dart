import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';

/// 💊 Splash Farmacia — versione con picker nativo (iOS/Android)
class SplashFarmacia extends StatelessWidget {
  const SplashFarmacia({super.key});

  Future<void> _openNativePicker(BuildContext context) async {
    final picker = ImagePicker();

    // Mostra un bottom sheet in stile iOS
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Scegli un'opzione",
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A97F3),
                  ),
                ),
                const SizedBox(height: 20),

                // 🔹 Fotocamera
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Color(0xFF1A97F3)),
                  title: Text(
                    "Scatta una foto",
                    style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
                    if (photo != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomePageWidget(imagePath: photo.path),
                        ),
                      );
                    }
                  },
                ),

                // 🔹 Galleria
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Color(0xFF38BDF8)),
                  title: Text(
                    "Scegli dalla libreria",
                    style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomePageWidget(imagePath: image.path),
                        ),
                      );
                    }
                  },
                ),

                // 🔹 File system (solo per iOS / Android >= 13)
                ListTile(
                  leading: const Icon(Icons.folder_open, color: Color(0xFF1A97F3)),
                  title: Text(
                    "Importa da File",
                    style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                    if (file != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomePageWidget(imagePath: file.path),
                        ),
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),
              ],
            ),
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

              // 🔹 Pulsante apri fotocamera (picker nativo)
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
                    onPressed: () => _openNativePicker(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Apri Fotocamera o Galleria",
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
                "Scatta la foto o scegli un'immagine per l'analisi",
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
