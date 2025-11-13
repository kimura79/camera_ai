import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:custom_camera_component/pages/home_page/home_page_widget.dart';
import 'package:custom_camera_component/pages/analysis_pharma_preview.dart';
import 'package:custom_camera_component/pages/analysis_preview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '/app_state.dart';

/// 💊 Splash Farmacia — reset totale a ogni apertura
class SplashFarmacia extends StatefulWidget {
  const SplashFarmacia({super.key});

  @override
  State<SplashFarmacia> createState() => _SplashFarmaciaState();
}

class _SplashFarmaciaState extends State<SplashFarmacia>
    with WidgetsBindingObserver {
  final ImagePicker picker = ImagePicker();

  // ============================================================
  // 🧹 PULIZIA COMPLETA (locale + remota)
  // ============================================================
  Future<void> _clearOldJobsAndFiles() async {
    try {
      // 🔹 1. Cancella job remoti
      const String serverUrl =
          "https://ray-stake-prediction-underground.trycloudflare.com";
      final uri = Uri.parse('$serverUrl/cancel_all_jobs');
      await http.post(uri);
      debugPrint("🧹 Tutti i job remoti cancellati.");

      // 🔹 2. Cancella file temporanei locali
      final tempDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();

      Future<void> cleanDir(Directory dir) async {
        if (await dir.exists()) {
          for (final file in dir.listSync(recursive: true)) {
            try {
              if (file is File &&
                  (file.path.contains('overlay_farmacia') ||
                      file.path.contains('overlay_') ||
                      file.path.contains('image_picker_') ||
                      file.path.contains('result_farmacia') ||
                      file.path.endsWith('.png') ||
                      file.path.endsWith('.json'))) {
                await file.delete();
                debugPrint("🗑️ Eliminato: ${file.path}");
              }
            } catch (_) {}
          }
        }
      }

      await cleanDir(tempDir);
      await cleanDir(appDir);

      debugPrint("🧹 Tutti i file temporanei locali eliminati.");
    } catch (e) {
      debugPrint("❌ Errore durante pulizia iniziale SplashFarmacia: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clearOldJobsAndFiles(); // ✅ pulizia automatica all'apertura
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ============================================================
  // 🔁 RICHIAMO AUTOMATICO QUANDO SI TORNA ALLA PAGINA
  // ============================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clearOldJobsAndFiles(); // ✅ ripulisce tutto anche al ritorno
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ si richiama anche quando si torna da una pagina interna
    WidgetsBinding.instance.addPostFrameCallback((_) => _clearOldJobsAndFiles());
  }

  // ============================================================
  // 📤 APERTURA ANALISI FARMACIA
  // ============================================================
  Future<void> _apriAnalisi(
      BuildContext context, String imagePath, String mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FFAppState().modalita == "farmacia"
            ? AnalysisPharmaPreview(imagePath: imagePath, mode: mode)
            : AnalysisPreview(imagePath: imagePath, mode: mode),
      ),
    );
    // ✅ Quando si torna, ripulisce subito
    await _clearOldJobsAndFiles();
  }

  // ============================================================
  // 🖼️ INTERFACCIA GRAFICA
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final parentContext = context;

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
                        context: parentContext,
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
                                    await Navigator.push(
                                      parentContext,
                                      MaterialPageRoute(
                                        builder: (_) => const HomePageWidget(),
                                      ),
                                    );
                                    await _clearOldJobsAndFiles();
                                  },
                                ),

                                // 🖼 Galleria
                                ListTile(
                                  leading: const Icon(Icons.photo_library,
                                      color: Color(0xFF38BDF8)),
                                  title: const Text("Galleria"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? image = await picker.pickImage(
                                        source: ImageSource.gallery);
                                    if (image != null) {
                                      await _apriAnalisi(
                                          parentContext, image.path, "fullface");
                                    }
                                  },
                                ),

                                // 📁 File
                                ListTile(
                                  leading: const Icon(Icons.folder,
                                      color: Color(0xFF60A5FA)),
                                  title: const Text("File"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? file = await picker.pickImage(
                                        source: ImageSource.gallery);
                                    if (file != null) {
                                      await _apriAnalisi(
                                          parentContext, file.path, "fullface");
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
