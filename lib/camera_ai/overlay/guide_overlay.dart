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
  final double phonePitch; // avanti/indietro (+ su, - giù)
  final double phoneRoll;  // sinistra/destra (+ dx, - sx)
  final Rect? faceRect;
  final (double?, double?, double?) faceAngles; // (pitch, yaw, roll) del volto
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

    // Overlay totalmente TRASPARENTE: nessun riempimento, solo linee/elementi UI
    return Stack(
      children: [
        // Cornice quadrato + tacche occhi
        Positioned.fromRect(
          rect: square,
          child: CustomPaint(
            painter: _SquarePainter(ok: _phoneOk && faceOk),
          ),
        ),

        // Valori numerici pitch/roll (tipo FaceID feedback)
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

        // Bolla ORIZZONTALE (roll) al centro del quadrato
        Positioned(
          left: square.left + 16,
          right: square.right - 16,
          top: square.center.dy - 10,
          height: 20,
          child: _BubbleLevelHorizontal(
            rollDeg: phoneRoll,
            tol: thresholds.phoneAngleTol,
          ),
        ),

        // Bolla VERTICALE (pitch) al centro del quadrato
        Positioned(
          top: square.top + 16,
          bottom: square.bottom - 16,
          left: square.center.dx - 10,
          width: 20,
          child: _BubbleLevelVertical(
            pitchDeg: phonePitch,
            tol: thresholds.phoneAngleTol,
          ),
        ),

        // Bbox volto + suggerimenti
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
    );
  }
}

/* -------------------- PITTORI E WIDGET GRAFICI -------------------- */

class _SquarePainter extends CustomPainter {
  final bool ok;
  _SquarePainter({required this.ok});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // bordo del quadrato (verde quando tutto ok)
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ok ? Colors.greenAccent : Colors.white;
    canvas.drawRect(rect, border);

    // banda "occhi" (40–55% dell’altezza)
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
  bool shouldRepaint(covariant _SquarePainter oldDelegate) =>
      oldDelegate.ok != ok;
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

    // suggerimenti
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

/* ---------- Livella numerica (chip Pitch/Roll) ---------- */

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
        color: Colors.black.withOpacity(0.55),
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

/* ---------- Livella a bolla: ORIZZONTALE (ROLL) ---------- */

class _BubbleLevelHorizontal extends StatelessWidget {
  final double rollDeg; // negativo=sinistra, positivo=destra
  final double tol;

  const _BubbleLevelHorizontal({required this.rollDeg, required this.tol});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleLevelHorizontalPainter(rollDeg: rollDeg, tol: tol),
    );
  }
}

class _BubbleLevelHorizontalPainter extends CustomPainter {
  final double rollDeg;
  final double tol;

  _BubbleLevelHorizontalPainter({required this.rollDeg, required this.tol});

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = 6.0;
    final radius = 10.0; // raggio bolla
    final barRect = RRect.fromRectXY(
      Rect.fromLTWH(0, (size.height - barHeight) / 2, size.width, barHeight),
      3, 3,
    );

    final ok = rollDeg.abs() <= tol;
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = ok ? Colors.greenAccent.withOpacity(0.75) : Colors.white70;

    // barra
    canvas.drawRRect(barRect, barPaint);

    // mappa gradi -> x bolla (clamp a ±15°)
    const maxDeg = 15.0;
    final clamped = rollDeg.clamp(-maxDeg, maxDeg);
    final t = (clamped + maxDeg) / (2 * maxDeg); // 0..1
    final cx = t * size.width;
    final cy = size.height / 2;

    final bubble = Paint()..color = Colors.black.withOpacity(0.65);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ok ? Colors.greenAccent : Colors.white;

    canvas.drawCircle(Offset(cx, cy), radius, bubble);
    canvas.drawCircle(Offset(cx, cy), radius, border);

    // tacca centrale (target)
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withOpacity(0.7);
    final midX = size.width / 2;
    canvas.drawLine(Offset(midX, cy - 10), Offset(midX, cy + 10), tick);
  }

  @override
  bool shouldRepaint(covariant _BubbleLevelHorizontalPainter oldDelegate) =>
      oldDelegate.rollDeg != rollDeg || oldDelegate.tol != tol;
}

/* ---------- Livella a bolla: VERTICALE (PITCH) ---------- */

class _BubbleLevelVertical extends StatelessWidget {
  final double pitchDeg; // negativo=giù, positivo=su
  final double tol;

  const _BubbleLevelVertical({required this.pitchDeg, required this.tol});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleLevelVerticalPainter(pitchDeg: pitchDeg, tol: tol),
    );
  }
}

class _BubbleLevelVerticalPainter extends CustomPainter {
  final double pitchDeg;
  final double tol;

  _BubbleLevelVerticalPainter({required this.pitchDeg, required this.tol});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 6.0;
    final radius = 10.0; // raggio bolla
    final barRect = RRect.fromRectXY(
      Rect.fromLTWH((size.width - barWidth) / 2, 0, barWidth, size.height),
      3, 3,
    );

    final ok = pitchDeg.abs() <= tol;
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = ok ? Colors.greenAccent.withOpacity(0.75) : Colors.white70;

    // barra verticale
    canvas.drawRRect(barRect, barPaint);

    // mappa gradi -> y bolla (clamp a ±15°)
    const maxDeg = 15.0;
    final clamped = pitchDeg.clamp(-maxDeg, maxDeg);
    // 0..1: 0 in alto (positivo su), 1 in basso
    final t = (maxDeg - clamped) / (2 * maxDeg);
    final cx = size.width / 2;
    final cy = t * size.height;

    final bubble = Paint()..color = Colors.black.withOpacity(0.65);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ok ? Colors.greenAccent : Colors.white;

    canvas.drawCircle(Offset(cx, cy), radius, bubble);
    canvas.drawCircle(Offset(cx, cy), radius, border);

    // tacca centrale (target)
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withOpacity(0.7);
    final midY = size.height / 2;
    canvas.drawLine(Offset(cx - 10, midY), Offset(cx + 10, midY), tick);
  }

  @override
  bool shouldRepaint(covariant _BubbleLevelVerticalPainter oldDelegate) =>
      oldDelegate.pitchDeg != pitchDeg || oldDelegate.tol != tol;
}