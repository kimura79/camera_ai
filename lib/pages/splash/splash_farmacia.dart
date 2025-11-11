// ============================================================
// 🏠 HomePageWidget — Schermata principale fotocamera
// Compatibile con picker nativo (imagePath) o guida statica (guideImage)
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/app_state.dart';
import '/index.dart';

class HomePageWidget extends StatefulWidget {
  final String? imagePath;   // ✅ percorso immagine passata dal picker
  final String? guideImage;  // ✅ immagine guida opzionale

  const HomePageWidget({
    super.key,
    this.imagePath,
    this.guideImage,
  });

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPreviewVisible = false;
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());

    // Se viene passata un'immagine dal picker nativo
    if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      debugPrint("📸 Immagine selezionata da picker: ${widget.imagePath}");
      setState(() {
        _isPreviewVisible = true;
      });
    } else {
      // Inizializza fotocamera se non è stata passata un’immagine
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera =
          cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.front);
      _cameraController = CameraController(frontCamera, ResolutionPreset.high);
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      debugPrint("📷 Fotocamera frontale inizializzata");
    } catch (e) {
      debugPrint("❌ Errore inizializzazione fotocamera: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (!_cameraController!.value.isInitialized) return;
    final image = await _cameraController!.takePicture();
    setState(() {
      _capturedImage = image;
      _isPreviewVisible = true;
    });
    debugPrint("✅ Foto scattata: ${image.path}");
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _cameraController!.value.aspectRatio,
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildImagePreview() {
    final path = widget.imagePath ?? _capturedImage?.path;
    if (path == null) {
      return const Center(child: Text("Nessuna immagine selezionata"));
    }
    return Image.file(File(path), fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 🔹 Mostra l'immagine selezionata o la fotocamera
            if (_isPreviewVisible) _buildImagePreview() else _buildCameraPreview(),

            // 🔹 Overlay guida (se presente)
            if (widget.guideImage != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.2,
                  child: Image.asset(
                    widget.guideImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // 🔹 Pulsante scatto / chiusura
            Positioned(
              bottom: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isPreviewVisible && _isCameraInitialized)
                    GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blueAccent, width: 4),
                        ),
                      ),
                    ),
                  if (_isPreviewVisible)
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isPreviewVisible = false;
                          _capturedImage = null;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        "Riprova",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                ],
              ),
            ),

            // 🔹 Titolo o icona in alto
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
