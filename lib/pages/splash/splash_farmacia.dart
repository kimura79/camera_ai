// ============================================================
// 💊 Splash Farmacia — schermata iniziale con selezione fotocamera/galleria
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';

class SplashFarmacia extends StatefulWidget {
  const SplashFarmacia({super.key});

  @override
  State<SplashFarmacia> createState() => _SplashFarmaciaState();
}

class _SplashFarmaciaState extends State<SplashFarmacia> {
  final ImagePicker _picker = ImagePicker();

  // 🔹 Apri fotocamera
  Future<void> _pickFromCamera() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomePageWidget(imagePath: photo.path),
        ),
      );
    }
  }

  // 🔹 Apri galleria
  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomePageWidget(imagePath: image.path),
        ),
      );
    }
  }

  // 🔹 Apri file (solo iOS 14+)
  Future<void> _pickFromFiles() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomePageWidget(imagePath: file.path),
        ),
      );
    }
  }

  // 🔹 Mostra bottom sheet nativo per scelta
  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Seleziona origine immagine",
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A97F3),
                ),
              ),
              const SizedBox(height: 15),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF1A97F3)),
                title: Text("Fotocamera", style: GoogleFonts.montserrat(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF38BDF8)),
                title: Text("Galleria", style: GoogleFonts.montserrat(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF60A5FA)),
                title: Text("File", style: GoogleFonts.montserrat(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromFiles();
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
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔹 Icona principale
              const Icon(Icons.local_pharmacy, color: Color(0xFF1A97F3), size: 90),
              const SizedBox(height: 30),

              // 🔹 Titolo doppia riga
              Text(
                "Epidermys\nTest Farmacie",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
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

              // 🔹 Pulsante principale
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
                    onPressed: _showPicker,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Apri Fotocamera / Galleria",
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

              Text(
                "Scatta o seleziona una foto per l’analisi (0–1)",
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
