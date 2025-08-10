import 'package:flutter/material.dart';

class GuideThresholds {
  final double phoneAngleTol;
  final double faceRollTol;
  final double faceYawTol;
  final double facePitchTol;
  final double bboxMin;
  final double bboxMax;

  const GuideThresholds({
    required this.phoneAngleTol,
    required this.faceRollTol,
    required this.faceYawTol,
    required this.facePitchTol,
    required this.bboxMin,
    required this.bboxMax,
  });
}

class GuideOverlay extends StatelessWidget {
  final Rect square;
  final double phonePitch;
  final double phoneRoll;
  final Rect? faceRect;
  final (double?, double?, double?) faceAngles; // (pitch, yaw, roll)
  final GuideThresholds thresholds;

  const GuideOverlay({
    super.key,
    required this.square,
    required this.phonePitch,
    required this.phoneRoll,
    required this.faceRect,
    required this.faceAngles,
    required this.thresholds,
  });

  bool get _phoneOk =>
      phonePitch.abs() <= thresholds.phoneAngleTol &&
      phoneRoll.abs() <= thresholds.phoneAngleTol;

  bool get _faceAnglesOk {
    final (p, y, r) = faceAngles;
    if (p == null || y == null || r == null) return false;
    return p.abs() <= thresholds.facePitchTol &&
        y.abs() <= thresholds.faceYawTol &&
        r.abs() <= thresholds.faceRollTol;
  }

  bool get _faceScaleOk {
    if (faceRect == null) return false;
    final ratio = faceRect!.height / square.width;
    return ratio >= thresholds.bboxMin && ratio <= thresholds.bboxMax;
  }

  bool get _faceCenterOk {
    if (faceRect == null) return false;
    return square.contains(faceRect!.center);
  }

  @override
  Widget build(BuildContext context) {
    final faceOk = _faceAnglesOk && _faceScaleOk && _faceCenterOk;

    return CustomPaint(
      painter: _MaskPainter(square: square),
      child: Stack(
        children: [
          // Cornice quadrato + tacche occhi
          Positioned.fromRect(
            rect: square,
            child: CustomPaint(
              painter: _SquarePainter(
                ok: _phoneOk && faceOk,
              ),
            ),
          ),

          // Livella sempre visibile (spostata DENTRO il quadrato)
          Positioned(
            top: square.top + 8,
            left: square.left + 8,
            right: square.right - 8,
            child: _LevelBar(
              pitch: phonePitch,
              roll: phoneRoll,
              tol: thresholds.phoneAngleTol,
            ),
          ),

          // Bbox volto e suggerimenti
          if (faceRect != null)
            Positioned.fromRect(
              rect: faceRect!,
              child: CustomPaint(
                painter: _FacePainter(
                  faceRect: faceRect!,
                  inCenter: _faceCenterOk,
                  inScale: _faceScaleOk,
                  anglesOk: _faceAnglesOk,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final Rect square;
  _MaskPainter({required this.square});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black.withOpacity(0.45);
    final clear = Paint()..blendMode = BlendMode.clear;

    // oscurare tutto
    canvas.drawRect(Offset.zero & size, bg);
    // foro quadrato
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(square, clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) =>
      oldDelegate.square != square;
}

class _SquarePainter extends CustomPainter {
  final bool ok;
  _SquarePainter({required this.ok});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ok ? Colors.greenAccent : Colors.white;

    // bordo
    canvas.drawRect(rect, border);

    // linea occhi (40–55% dell’altezza)
    final y1 = rect.top + rect.height * 0.40;
    final y2 = rect.top + rect.height * 0.55;
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white70;
    canvas.drawLine(Offset(rect.left, y1), Offset(rect.right, y1), guide);
    canvas.drawLine(Offset(rect.left, y2), Offset(rect.right, y2), guide);

    // crocetta centrale
    final c = rect.center;
    canvas.drawLine(Offset(c.dx - 12, c.dy), Offset(c.dx + 12, c.dy), guide);
    canvas.drawLine(Offset(c.dx, c.dy - 12), Offset(c.dx, c.dy + 12), guide);
  }

  @override
  bool shouldRepaint(covariant _SquarePainter oldDelegate) => oldDelegate.ok != ok;
}

class _FacePainter extends CustomPainter {
  final Rect faceRect;
  final bool inCenter;
  final bool inScale;
  final bool anglesOk;

  _FacePainter({
    required this.faceRect,
    required this.inCenter,
    required this.inScale,
    required this.anglesOk,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ok = inCenter && inScale && anglesOk;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ok ? Colors.lightGreenAccent : Colors.orangeAccent;

    canvas.drawRect(Offset.zero & size, p);

    // suggerimenti semplici
    final textPainter = (String t) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      return tp;
    };

    final hints = <String>[];
    if (!inScale) hints.add('Avvicina/Allontana');
    if (!inCenter) hints.add('Centra il volto');
    if (!anglesOk) hints.add('Raddrizza il volto');

    if (hints.isNotEmpty) {
      final tp = textPainter(hints.join(' • '));
      tp.paint(canvas, Offset(4, -tp.height - 6));
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.inCenter != inCenter ||
      oldDelegate.inScale != inScale ||
      oldDelegate.anglesOk != anglesOk ||
      oldDelegate.faceRect != faceRect;
}

class _LevelBar extends StatelessWidget {
  final double pitch;
  final double roll;
  final double tol;

  const _LevelBar({required this.pitch, required this.roll, required this.tol});

  @override
  Widget build(BuildContext context) {
    final ok = pitch.abs() <= tol && roll.abs() <= tol;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip('Pitch', pitch, ok),
        const SizedBox(width: 8),
        _chip('Roll', roll, ok),
      ],
    );
  }

  Widget _chip(String label, double val, bool ok) {
    final txt = '${val.toStringAsFixed(1)}°';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55), // più visibile
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? Colors.greenAccent : Colors.white54),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 6),
          Text(txt, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}