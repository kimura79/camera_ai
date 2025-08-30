import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 🔹 Overlay per mostrare la distanza stimata in cm sotto il riquadro 1:1.
Widget buildDistanzaCmOverlay({
  required double ipdPx,
  double ipdMm = 63.0,
  double targetMmPerPx = 0.117,
  double alignY = 0.4,
}) {
  String testo;
  if (ipdPx <= 0 || !ipdPx.isFinite) {
    testo = '— cm';
  } else {
    final mmPerPxAttuale = ipdMm / ipdPx;
    final distCm = 55.0 * (mmPerPxAttuale / targetMmPerPx);
    testo = '${distCm.toStringAsFixed(1)} cm';
  }

  return Align(
    alignment: Alignment(0, alignY),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        testo,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}