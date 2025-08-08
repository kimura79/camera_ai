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
  _CameraPhotoState createState() => _CameraPhotoState();
}

class _CameraPhotoState extends State<CameraPhoto> {
  CameraController? controller;
  late Future<List<CameraDescription>> _cameras;

  @override
  void initState() {
    super.initState();
    _cameras = availableCameras();
  }

  @override
  void didUpdateWidget(covariant CameraPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (FFAppState().makePhoto && controller != null && controller!.value.isInitialized) {
      controller!.takePicture().then((file) async {
        Uint8List fileAsBytes = await file.readAsBytes();
        final base64 = base64Encode(fileAsBytes);

        // salva base64 nello stato globale
        FFAppState().update(() {
          FFAppState().fileBase64 = base64;
        });

        // salva anche path per thumbnail
        FFAppState().update(() {
          FFAppState().lastPhotoPath = file.path;
        });

        FFAppState().update(() {
          FFAppState().makePhoto = false;
        });
      }).catchError((error) {});
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CameraDescription>>(
      future: _cameras,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            if (controller == null) {
              // prendi sempre la camera posteriore principale
              final CameraDescription backCamera = snapshot.data!
                  .firstWhere((cam) => cam.lensDirection == CameraLensDirection.back);

              controller = CameraController(
                backCamera,
                ResolutionPreset.max,
                enableAudio: false,
              );

              controller!.initialize().then((_) async {
                if (!mounted) return;

                // Blocca orientamento verticale
                await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

                // Blocca zoom a 1x (evita ultra-grandangolo 0.5x)
                final minZoom = await controller!.getMinZoomLevel();
                final maxZoom = await controller!.getMaxZoomLevel();
                await controller!.setZoomLevel(1.0.clamp(minZoom, maxZoom));

                // Auto focus + esposizione
                await controller!.setFocusMode(FocusMode.auto);
                await controller!.setExposureMode(ExposureMode.auto);

                setState(() {});
              });
            }

            return controller!.value.isInitialized
                ? AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: CameraPreview(controller!),
                  )
                : Container();
          } else {
            return const Center(child: Text('No cameras available.'));
          }
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}