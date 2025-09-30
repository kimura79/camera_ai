import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show Platform;

/// 🔹 Overlay per mostrare la distanza stimata in cm.
/// - In modalità "fullface": invariata.
/// - In modalità "particolare": 1024×1024, diventa verde a 12 cm ± tolleranza.
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  required bool isFrontCamera,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,   // target scala volto
  double alignY = 0.4,
  String mode = "fullface",       // 👈 ora è String come negli altri file
}) {
  String testo;
  Color borderColor = Colors.yellow;

  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    if (mode == "fullface") {
      final mmPerPxAttuale = ipdMm / ipdPx;
      final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);

      // ✅ corretto: mostra cm se tra 5 e 100, non sparisce a 50 cm
      if (distCm > 5 && distCm < 100) {
        testo = '${distCm.toStringAsFixed(1)} cm';
      } else {
        testo = '— cm';  // valori assurdi nascosti
      }

      borderColor = Colors.green;
    } else {
      final mmPerPxAttuale = ipdMm / ipdPx;
      final larghezzaRealeMm = mmPerPxAttuale * 1024.0;
      final distanzaCm = (larghezzaRealeMm / 10.0) * 2.0;

      if (distanzaCm > 5 && distanzaCm < 50) {
        testo = '${distanzaCm.toStringAsFixed(1)} cm';
      } else {
        testo = '— cm';
      }

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
