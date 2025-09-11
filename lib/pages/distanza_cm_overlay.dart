import 'package:flutter/material.dart';
import 'dart:io' show Platform;

import 'package:custom_camera_component/pages/home_page/home_page_widget.dart'
    show CaptureMode;

/// 🔹 Overlay per mostrare la distanza stimata in cm.
/// - VOLTO: logica originale.
/// - PARTICOLARE: riquadro verde solo quando il crop = ~12 cm reali.
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117, // target: 12 cm su 1024 px
  double alignY = 0.4,
  CaptureMode mode = CaptureMode.volto,
}) {
  String testo = '— cm';
  Color borderColor = Colors.yellow; // default giallo

  if (ipdPx > 0 && ipdPx.isFinite) {
    if (mode == CaptureMode.volto) {
      // ✅ logica originale volto intero
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
      testo = '${distCm.toStringAsFixed(1)} cm';
      borderColor = Colors.green;
    } else {
      // ✅ logica per particolari
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;
      final larghezzaRealeCm = (larghezzaRealeMm / 10.0) * 2.0; // correzione ×2

      testo = '${larghezzaRealeCm.toStringAsFixed(1)} cm';

      // Riquadro verde solo se ≈ 12 cm
      if (larghezzaRealeCm > 11.5 && larghezzaRealeCm < 12.5) {
        borderColor = Colors.green;
      }
    }
  }

  return Align(
    alignment: Alignment(0, alignY),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2.0),
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