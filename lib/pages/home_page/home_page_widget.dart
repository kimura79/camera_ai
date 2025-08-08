// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class CameraPhoto extends StatefulWidget {
  const CameraPhoto({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  final double? width;
  final double? height;

  @override
  State<CameraPhoto> createState() => _CameraPhotoState();
}

class _CameraPhotoState extends State<CameraPhoto> {
  CameraController? _controller;
  late Future<List<CameraDescription>> _cameras;
  bool _initializing = false;
  bool _shooting = false; // evita doppi scatti

  @override
  void initState() {
    super.initState();
    _cameras = availableCameras();
  }

  @override
  void didUpdateWidget(covariant CameraPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Se è arrivato il segnale di scatto dallo stato globale
    if (FFAppState().makePhoto == true &&
        _controller != null &&
        _controller!.value.isInitialized &&
        !_shooting) {
      _takePicture();
    }
  }

  Future<void> _initController(List<CameraDescription> cams) async {
    if (_initializing) return;
    _initializing = true;

    try {
      // Prendi la camera posteriore "wide" (non ultra‑wide)
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      // Blocca orientamento in verticale
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Blocca zoom ≈ 1x (evita 0.5x)
      final minZ = await controller.getMinZoomLevel();
      final maxZ = await controller.getMaxZoomLevel();
      await controller.setZoomLevel(1.0.clamp(minZ, maxZ));

      // Auto fuoco / esposizione
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      // opzionale: mostrare errore a schermo
      debugPrint('Camera init error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _shooting = true;

    try {
      // Scatta
      final XFile file = await _controller!.takePicture();

      // Leggi bytes e scrivi nel FFAppState
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);

      FFAppState().update(() {
        FFAppState().fileBase64 = base64;
        FFAppState().makePhoto = false; // reset del trigger
      });
    } catch (e) {
      debugPrint('takePicture error: $e');
      FFAppState().update(() => FFAppState().makePhoto = false);
    } finally {
      _shooting = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CameraDescription>>(
      future: _cameras,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return const Center(child: Text('No cameras available.'));
        }

        // inizializza una volta
        if (_controller == null && !_initializing) {
          _initController(snap.data!);
        }

        if (_controller == null || !_controller!.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        // Preview non distorta, a schermo pieno
        final previewSize = _controller!.value.previewSize;
        final w = previewSize?.height ?? 1080; // iOS portrait swap
        final h = previewSize?.width ?? 1920;

        return SizedBox(
          width: widget.width ?? double.infinity,
          height: widget.height ?? double.infinity,
          child: FittedBox(
            fit: BoxFit.cover, // riempi senza stirare
            child: SizedBox(
              width: w,
              height: h,
              child: CameraPreview(_controller!),
            ),
          ),
        );
      },
    );
  }
}