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
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    _cameras = availableCameras();
  }

  @override
  void didUpdateWidget(covariant CameraPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final c = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);

      final minZ = await c.getMinZoomLevel();
      final maxZ = await c.getMaxZoomLevel();
      await c.setZoomLevel(1.0.clamp(minZ, maxZ));

      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);

      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _shooting = true;
    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      FFAppState().update(() {
        FFAppState().fileBase64 = b64;
        FFAppState().makePhoto = false;
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

        if (_controller == null && !_initializing) {
          _initController(snap.data!);
        }
        if (_controller == null || !_controller!.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        final previewSize = _controller!.value.previewSize;
        final w = previewSize?.height ?? 1080; // iOS portrait swap
        final h = previewSize?.width ?? 1920;

        return SizedBox(
          width: widget.width ?? double.infinity,
          height: widget.height ?? double.infinity,
          child: FittedBox(
            fit: BoxFit.cover,
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