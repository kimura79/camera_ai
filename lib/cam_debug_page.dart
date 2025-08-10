import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CamDebugPage extends StatefulWidget {
  const CamDebugPage({super.key});
  @override
  State<CamDebugPage> createState() => _CamDebugPageState();
}

class _CamDebugPageState extends State<CamDebugPage> {
  CameraController? c;
  List<CameraDescription> cams = [];
  String? err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      cams = await availableCameras();
      if (cams.isEmpty) { setState(() => err = 'Nessuna camera'); return; }
      c = CameraController(
        cams.first, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      setState(() => err = '$e');
    }
  }

  @override
  void dispose() { c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (err != null) {
      return Scaffold(body: Center(child: Text('ERRORE: $err')));
    }
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!c!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('CamDebugPage')),
      body: CameraPreview(c!),
    );
  }
}