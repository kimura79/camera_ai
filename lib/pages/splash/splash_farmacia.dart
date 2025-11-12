import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';
import 'package:custom_camera_component/pages/analysis_pharma_preview.dart';
import 'package:custom_camera_component/pages/analysis_preview.dart';
import '/app_state.dart';

/// 💊 Splash Farmacia (sfondo bianco + selettore fotocamera/galleria/file)
class SplashFarmacia extends StatelessWidget {
  const SplashFarmacia({super.key});

  Future<void> _apriAnalisi(
      BuildContext context, String imagePath, String mode) async {
    // 🔁 stessa logica dello scatto in HomePageWidget
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FFAppState().modalita == "farmacia"
            ? AnalysisPharmaPreview(imagePath: imagePath, mode: mode)
            : AnalysisPreview(imagePath: imagePath, mode: mode),
      ),
    ).then((analyzed) {
      if (analyzed != null) {
        Navigator.pop(context);
        Navigator.pop(context, analyzed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ImagePicker picker = ImagePicker();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_pharmacy,
                color: Color(0xFF1A97F3),
                size: 90,
              ),
              const SizedBox(height: 30),
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
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) {
                          return SafeArea(
                            child: Wrap(
                              children: [
                                // 📷 Fotocamera — apre HomePageWidget
                                ListTile(
                                  leading: const Icon(Icons.camera_alt,
                                      color: Color(0xFF1A97F3)),
                                  title: const Text("Fotocamera"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const HomePageWidget(),
                                      ),
                                    );
                                  },
                                ),

                                // 🖼 Galleria — apre direttamente la pagina di analisi
                                ListTile(
                                  leading: const Icon(Icons.photo_library,
                                      color: Color(0xFF38BDF8)),
                                  title: const Text("Galleria"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? image = await picker.pickImage(
                                        source: ImageSource.gallery);
                                    if (image != null && context.mounted) {
                                      Future.delayed(Duration.zero, () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AnalysisPharmaPreview(
                                              imagePath: image.path,
                                              mode: "fullface",
                                            ),
                                          ),
                                        );
                                      });
                                    }
                                  },
                                ),

                                // 📁 File — apre direttamente la pagina di analisi
                                ListTile(
                                  leading: const Icon(Icons.folder,
                                      color: Color(0xFF60A5FA)),
                                  title: const Text("File"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? file = await picker.pickImage(
                                        source: ImageSource.gallery);
                                    if (file != null && context.mounted) {
                                      Future.delayed(Duration.zero, () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AnalysisPharmaPreview(
                                              imagePath: file.path,
                                              mode: "fullface",
                                            ),
                                          ),
                                        );
                                      });
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

              Text(
                "Scatta o seleziona un'immagine per analizzare la pelle",
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
