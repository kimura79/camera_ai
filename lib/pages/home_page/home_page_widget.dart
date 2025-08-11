import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

const double squareScale = 0.86; // SOLO bordo guida

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});
  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  String? _lastPhotoPath;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

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

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _initError = true);
        return;
      }
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _initError = true);
    }
  }

  Future<void> _reinitCamera() async {
    await _disposeCamera();
    await _initCamera();
  }

  Future<void> _disposeCamera() async {
    try { await _controller?.dispose(); } catch (_) {}
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
      final outPath = '${dir.path}/last_shot_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Errore inizializzazione fotocamera.\nControlla i permessi iOS.', textAlign: TextAlign.center)),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth, h = c