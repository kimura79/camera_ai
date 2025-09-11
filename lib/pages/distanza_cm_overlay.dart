import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:custom_camera_component/pages/home_page/home_page_widget.dart' show CaptureMode;

/// 🔹 Overlay per mostrare la distanza stimata in cm.
/// - In modalità VOLTO: invariata.
/// - In modalità PARTICOLARE: 1024×1024, diventa verde a 12 cm ± tolleranza.
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,   // target scala volto
  double alignY = 0.4,
  CaptureMode mode = CaptureMode.volto,
}) {
  String testo;
  Color borderColor = Colors.yellow;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    if (mode == CaptureMode.volto) {
      // ✅ logica originale per volto intero (NON TOCCATA)
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
      testo = '${distCm.toStringAsFixed(1)} cm';
      borderColor = Colors.green; // volto sempre verde quando in range
    } else {
      // ✅ logica aggiornata per PARTICOLARE
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;

      // distanza stimata in cm (moltiplicatore calibrato ×2)
      final distanzaCm = (larghezzaRealeMm / 10.0) * 2.0;

      testo = '${distanzaCm.toStringAsFixed(1)} cm';

      // Verde solo se vicino a 12 cm (11–13 cm)
      if ((distanzaCm - 12.0).abs() <= 1.0) {
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