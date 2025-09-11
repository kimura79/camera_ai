import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show Platform;


/// 🔹 Overlay per mostrare la distanza stimata in cm sotto il riquadro 1:1.
/// - In modalità VOLTO: mantiene la logica originale (stabile).
/// - In modalità PARTICOLARE: usa la formula geometrica basata sul FOV.
/// - Adatta il FOV se la camera è frontale vs posteriore.
Widget buildDistanzaCmOverlay({
  required double ipdPx,          // distanza pupille in pixel
  required bool isFrontCamera,    // true se fotocamera frontale
  double ipdMm = 63.0,            // distanza pupille reale in mm
  double targetMmPerPx = 0.117,   // scala target
  double alignY = 0.4,            // posizione verticale
  required CaptureMode mode,      // 👈 enum importato da home_page_widget.dart
}) {
  String testo;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    if (mode == CaptureMode.volto) {
      // ✅ logica originale per il volto intero
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
      testo = '${distCm.toStringAsFixed(1)} cm';
    } else {
      // ✅ formula geometrica per particolari
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;

      // FOV differenziato
      double fovDeg;
      if (isFrontCamera) {
        fovDeg = 60.0; // frontale iPhone
      } else {
        fovDeg = Platform.isAndroid ? 67.0 : 64.0; // back: Android / iPhone
      }

      final double fovRad = fovDeg * math.pi / 180.0;
      final distanzaMm = larghezzaRealeMm / (2 * math.tan(fovRad / 2));
      final distanzaCm = distanzaMm / 10.0;

      testo = '${distanzaCm.toStringAsFixed(1)} cm';
    }
  }

  return Align(
    alignment: Alignment(0, alignY),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1.0),
      ),
      child: Text(
        testo,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
