import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Ritorna true se la rotazione è 90 o 270 gradi
bool isRotation90or270(int degrees) => degrees % 180 != 0;

/// Mappa un rettangolo in coordinate immagine -> coordinate preview (widget),
/// sapendo che la preview usa BoxFit.cover.
Rect mapImageRectToPreview({
  required Rect imageRect,
  required Size imageSize,
  required Size previewSize,
  required BoxFit fit,
  required bool mirrorPreview, // true se la preview è specchiata (selfie)
}) {
  assert(fit == BoxFit.cover, 'Questo mapping assume cover.');

  final scale = math.max(previewSize.width / imageSize.width, previewSize.height / imageSize.height);
  final displayW = imageSize.width * scale;
  final displayH = imageSize.height * scale;

  final dx = (displayW - previewSize.width) / 2;
  final dy = (displayH - previewSize.height) / 2;

  Offset mapPoint(Offset p) {
    final sx = p.dx * scale - dx;
    final sy = p.dy * scale - dy;
    if (mirrorPreview) {
      final mirroredX = previewSize.width - sx;
      return Offset(mirroredX, sy);
    }
    return Offset(sx, sy);
  }

  final tl = mapPoint(imageRect.topLeft);
  final br = mapPoint(imageRect.bottomRight);
  return Rect.fromPoints(tl, br);
}

/// Mappa un rettangolo del preview (overlay) -> coordinate dell'immagine scattata,
/// sapendo che CameraPreview usa cover.
Rect mapPreviewRectToImage({
  required Rect overlayInPreview,
  required Size previewSize,
  required Size imageSize,
  required BoxFit fit,
  required bool mirrorPreview, // true se la preview è specchiata (selfie)
}) {
  assert(fit == BoxFit.cover, 'Questo mapping assume cover.');

  final scale = math.max(previewSize.width / imageSize.width, previewSize.height / imageSize.height);
  final displayW = imageSize.width * scale;
  final displayH = imageSize.height * scale;

  final dx = (displayW - previewSize.width) / 2;
  final dy = (displayH - previewSize.height) / 2;

  Offset invMap(Offset p) {
    var px = p.dx;
    if (mirrorPreview) {
      px = previewSize.width - px; // inverti perché la preview è specchiata
    }
    final x = (px + dx) / scale;
    final y = (p.dy + dy) / scale;
    return Offset(x, y);
  }

  final tl = invMap(overlayInPreview.topLeft);
  final br = invMap(overlayInPreview.bottomRight);
  final rect = Rect.fromPoints(tl, br);

  final clamped = Rect.fromLTWH(
    rect.left.clamp(0.0, imageSize.width.toDouble()),
    rect.top.clamp(0.0, imageSize.height.toDouble()),
    (rect.width).clamp(1.0, imageSize.width.toDouble()),
    (rect.height).clamp(1.0, imageSize.height.toDouble()),
  );
  return clamped;
}

/// Croppa con sicurezza (clamping) un’immagine con rettangolo float
img.Image cropSafe(img.Image source, Rect r) {
  final x = r.left.round().clamp(0, source.width - 1);
  final y = r.top.round().clamp(0, source.height - 1);
  final w = r.width.round().clamp(1, source.width - x);
  final h = r.height.round().clamp(1, source.height - y);
  return img.copyCrop(source, x: x, y: y, width: w, height: h);
}