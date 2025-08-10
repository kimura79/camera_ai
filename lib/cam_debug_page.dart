import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CamDebugPageStandalone extends StatefulWidget {
  const CamDebugPageStandalone({super.key});

  @override
  State<CamDebugPageStandalone> createState() => _CamDebugPageStandaloneState();
}

class _CamDebugPageStandaloneState extends State<CamDebugPageStandalone> {
  CameraController? c;
  List<CameraDescription> cams = [];
  String status = 'init...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      status = 'widgets ready';
      WidgetsFlutterBinding.ensureInitialized();
      status = 'asking cameras...';
      cams = await availableCameras();
      if (cams.isEmpty) { setState(() => status = 'Nessuna camera'); return; }
      status = 'creating controller...';
      c = CameraController(
        cams.first, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420,
      );
      status = 'initializing controller...';
      await c!.initialize();
      if (!mounted) return;
      setState(() => status = 'ok');
    } catch (e) {
      setState(() => status = 'ERRORE: $e');
    }
  }

  @override
  void dispose() { c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final diag = Container(
      color: Colors.black54,
      padding: const EdgeInsets.all(8),
      child: Text(
        'diag: $status | '
        'cams:${cams.length} | '
        'inited:${c?.value.isInitialized == true} | '
        'hasErr:${c?.value.hasError == true} | '
        'err:${c?.value.errorDescription ?? '-'}',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );

    if (c == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('CamDebug')),
        body: Center(child: diag),
      );
    }
    if (!c!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('CamDebug')),
        body: Column(
          children: [
            diag,
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('CamDebug')),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(c!)),
          Positioned(top: 0, left: 0, right: 0, child: diag),
        ],
      ),
    );
  }
}