import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:custom_camera_component/pages/home_page/home_page_widget.dart' show CaptureMode;

/// 🔹 Overlay per mostrare la distanza stimata in cm.
/// - In modalità VOLTO: mantiene la logica originale (stabile).
/// - In modalità PARTICOLARE: scala aggiornata + moltiplicatore di calibrazione.
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,   // target: 12 cm in 1024 px
  double alignY = 0.4,
  CaptureMode mode = CaptureMode.volto,
}) {
  String testo;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    if (mode == CaptureMode.volto) {
      // ✅ logica originale per volto intero
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
      testo = '${distCm.toStringAsFixed(1)} cm';
    } else {
      // ✅ logica aggiornata per particolari
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;

      // distanza stimata in cm (senza FOV)
      final distanzaCm = larghezzaRealeMm / 10.0;

      // moltiplicatore empirico per calibrare (senza dimezzamenti)
      final calibrazione = 2.0;
      final distanzaCorrettaCm = distanzaCm * calibrazione;

      testo = '${distanzaCorrettaCm.toStringAsFixed(1)} cm';
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
