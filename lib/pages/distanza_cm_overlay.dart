import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show Platform;

/// 🔹 Overlay per mostrare la distanza stimata in cm sotto il riquadro 1:1.
/// Calcolo basato su IPD rilevato e FOV medio per iOS / Android.
Widget buildDistanzaCmOverlay({
  required double ipdPx,          // distanza pupille in pixel
  double ipdMm = 63.0,            // distanza pupille reale in mm (default: 63 mm)
  double targetMmPerPx = 0.117,   // scala target
  double alignY = 0.4,            // posizione verticale
}) {
  String testo;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    // 1. Calcolo scala attuale (mm/px)
    final mmPerPxAttuale = ipdMm / ipdPx;

    // 2. Larghezza reale del crop 1024 px
    final larghezzaRealeMm = mmPerPxAttuale * 1024.0;

    // 3. Angolo di campo medio
    double fovDeg = 64.0; // default iPhone 11–15
    if (Platform.isAndroid) {
      fovDeg = 67.0; // media Pixel/Samsung
    }
    final double fovRad = fovDeg * math.pi / 180.0;

    // 4. Distanza stimata in mm → cm
    final distanzaMm = larghezzaRealeMm / (2 * math.tan(fovRad / 2));
    final distanzaCm = distanzaMm / 10.0;

    // 5. Testo
    testo = '${distanzaCm.toStringAsFixed(1)} cm';
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