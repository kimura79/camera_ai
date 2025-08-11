import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const double squareScale = 0.86; // bordo guida 1:1 (solo contorno)

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});
  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;

  String? _lastPhotoPath;

  bool _initError = false;
  bool _requestingPermission = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1) chiedi permesso → 2) se ok, inizializza camera
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _ensureCameraPermission();
      if (!mounted) return;
      if (ok) {
        await _initCamera();
      } else {
        setState(() {
          _initError = true;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  // Gestione lifecycle: evita nero al rientro su iOS
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.inactive) {
      await c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await _reinitCamera();
    }
  }

  /* ====== Permessi ====== */
  Future<bool> _ensureCameraPermission() async {
    setState(() => _requestingPermission = true);

    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() => _requestingPermission = false);
      return true;
    }

    final res = await Permission.camera.request();
    setState(() => _requestingPermission = false);

    return res.isGranted;
  }

  /* ====== Camera ====== */
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _initError = true);
        return;
      }

      // preferisci frontale (selfie); altrimenti prima disponibile
      final preferred = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        preferred,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _initError = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore inizializzazione fotocamera: $e')),
      );
    }
  }

  Future<void> _reinitCamera() async {
    await _disposeCamera();
    await _initCamera();
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty || _controller == null) return;

    final current = _controller!.description;
    CameraDescription next = current;

    if (_cameras.length > 1) {
      if (current.lensDirection == CameraLensDirection.front) {
        next = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => current,
        );
      } else {
        next = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => current,
        );
      }
    }

    await _controller?.dispose();
    _controller = CameraController(
      next,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    try {
      final xfile = await c.takePicture();
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/last_shot_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(xfile.path).copy(outPath);
      if (!mounted) return;
      setState(() => _lastPhotoPath = outPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Foto salvata (temporanea)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore scatto: $e')),
      );
    }
  }

  /* ====== UI ====== */
  @override
  Widget build(BuildContext context) {
    // 1) fase richiesta permesso
    if (_requestingPermission) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2) errore o permesso negato
    if (_initError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Impossibile usare la fotocamera.\n'
                  'Controlla i permessi in Impostazioni.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    await openAppSettings();
                  },
                  child: const Text('Apri Impostazioni'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final ok = await _ensureCameraPermission();
                    if (ok) {
                      await _initCamera();
                    }
                  },
                  child: const Text('Riprova'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3) in attesa inizializzazione controller
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 4) camera ok
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;

          // bordo guida 1:1 (solo bordo)
          final side = (w < h ? w : h) * squareScale;
          final left = (w - side) / 2;
          final top = (h - side) / 2;

          // anteprima specchiata se frontale (stile nativo)
          final preview =
              _controller!.description.lensDirection == CameraLensDirection.front
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                      child: CameraPreview(_controller!),
                    )
                  : CameraPreview(_controller!);

          return Stack(
            children: [
              // Preview full screen
              Positioned.fill(child: preview),

              // Bordo guida 1:1
              Positioned(
                left: left,
                top: top,
                width: side,
                height: side,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

              // Thumbnail in basso a sinistra
              if (_lastPhotoPath != null)
                Positioned(
                  left: 16,
                  bottom: 24,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_lastPhotoPath!),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              // Switch camera in basso a destra
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton(
                  heroTag: 'switchCam',
                  mini: true,
                  backgroundColor: Colors.black54,
                  onPressed: _switchCamera,
                  child: const Icon(Icons.cameraswitch, color: Colors.white),
                ),
              ),

              // Pulsante scatto al centro in basso
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: GestureDetector(
                    onTap: _shoot,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                        Container(
                          width: 66,
                          height: 66,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}