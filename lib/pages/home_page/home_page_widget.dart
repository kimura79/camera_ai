import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

import 'package:gallery_saver/gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

// 📌 Costante per regolare altezza riquadro guida (da -1 = in alto a 1 = in basso)
const double squareOffsetY = -0.5;

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<FFUploadedFile?> _cropAndResizeTo1024(FFUploadedFile src) async {
    try {
      final bytes = src.bytes;
      if (bytes == null) return null;

      final original = img.decodeImage(bytes);
      if (original == null) return null;

      final size = original.width < original.height ? original.width : original.height;
      final x = (original.width - size) ~/ 2;
      final y = (original.height - size) ~/ 2;
      final cropped = img.copyCrop(original, x: x, y: y, width: size, height: size);

      final resized = img.copyResize(cropped, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);

      final outBytes = img.encodeJpg(resized, quality: 100);

      return FFUploadedFile(bytes: outBytes, name: 'face_1024.jpg');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBytesToGallery(List<int> bytes) async {
    final tempPath = '${Directory.systemTemp.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(tempPath);
    await f.writeAsBytes(bytes, flush: true);
    await GallerySaver.saveImage(f.path);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primary,
          automaticallyImplyLeading: false,
          title: Text(
            'Custom Camera',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  color: Colors.white,
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                ),
          ),
          centerTitle: false,
          elevation: 2.0,
        ),
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              // Preview camera full screen
              Positioned.fill(
                child: custom_widgets.CameraPhoto(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              // Riquadro guida regolabile
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final size = w < h ? w : h;

                  return IgnorePointer(
                    child: Align(
                      alignment: Alignment(0, squareOffsetY),
                      child: Container(
                        width: size * 0.9,
                        height: size * 0.9,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Pulsante scatto reattivo
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: FFButtonWidget(
                    onPressed: () async {
                      FFAppState().makePhoto = true;
                      safeSetState(() {});

                      // Se il widget CameraPhoto ha bisogno di un attimo per scrivere fileBase64,
                      // si può mettere un piccolo delay di sicurezza:
                      await Future.delayed(const Duration(milliseconds: 100));

                      final rawTaken = functions.base64toFile(FFAppState().fileBase64);
                      if (rawTaken == null || rawTaken.bytes == null) return;

                      final processed = await _cropAndResizeTo1024(rawTaken);
                      if (processed == null || processed.bytes == null) return;

                      await _saveBytesToGallery(processed.bytes!);

                      context.pushNamed(
                        BsImageWidget.routeName,
                        queryParameters: {
                          'imageparam': serializeParam(
                            processed,
                            ParamType.FFUploadedFile,
                          ),
                        }.withoutNulls,
                      );
                    },
                    text: 'Take Picture',
                    options: FFButtonOptions(
                      height: 58.0,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      color: FlutterFlowTheme.of(context).primary,
                      textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FlutterFlowTheme.of(context)
                                  .titleSmall
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .titleSmall
                                  .fontStyle,
                            ),
                            color: Colors.white,
                            letterSpacing: 0.0,
                          ),
                      elevation: 0.0,
                      borderRadius: BorderRadius.circular(32.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
