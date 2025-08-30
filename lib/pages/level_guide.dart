import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Livella orizzontale stile iOS: tre linee che si fondono in una verde
/// quando il telefono è allineato frontalmente al soggetto.
class LevelGuide extends StatefulWidget {
  const LevelGuide({super.key});

  @override
  State<LevelGuide> createState() => _LevelGuideState();
}

class _LevelGuideState extends State<LevelGuide> {
  StreamSubscription? _accSub;

  double _rollDeg = 0;
  double _pitchDeg = 0;
  double _rollFilt = 0;
  double _pitchFilt = 0;

  static const _alpha = 0.12;

  @override
  void initState() {
    super.initState();
    _accSub = accelerometerEventStream().listen(_onAccelerometer);
  }

  @override
  void dispose() {
    _accSub?.cancel();
    super.dispose();
  }

  void _onAccelerometer(AccelerometerEvent e) {
    final rollRad = math.atan2(e.y, e.z);
    final pitchRad = math.atan2(-e.x, math.sqrt(e.y * e.y + e.z * e.z));

    final roll = rollRad * 180 / math.pi;
    final pitch = pitchRad * 180 / math.pi;

    _rollFilt = _rollFilt + _alpha * (roll - _rollFilt);
    _pitchFilt = _pitchFilt + _alpha * (pitch - _pitchFilt);

    setState(() {
      _rollDeg = _rollFilt;
      _pitchDeg = _pitchFilt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rollErr = _rollDeg;
    final pitchOk = _pitchDeg.abs() <= 3.0;

    double offset = (rollErr.abs() * 2.0).clamp(0, 28.0);
    final aligned = rollErr.abs() <= 1.0 && pitchOk;
    if (aligned) offset = 0;

    final baseColor = Colors.white.withOpacity(0.9);
    final okColor = Colors.greenAccent.withOpacity(0.95);

    final thick = aligned ? 3.5 : 2.0;

    return IgnorePointer(
      ignoring: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final centerY = c.maxHeight / 2; // 🔹 centro del riquadro 1:1
          final lineWidth = c.maxWidth * 0.5;
          final x = (c.maxWidth - lineWidth) / 2;

          return Stack(
            children: [
              // Linea centrale
              Positioned(
                left: x,
                top: centerY,
                child: _Line(
                  width: lineWidth,
                  thickness: thick,
                  color: aligned ? okColor : baseColor.withOpacity(0.55),
                ),
              ),
              // Linea sopra
              Positioned(
                left: x,
                top: centerY - offset,
                child: _Line(
                  width: lineWidth,
                  thickness: 2.0,
                  color: aligned ? Colors.transparent : baseColor,
                ),
              ),
              // Linea sotto
              Positioned(
                left: x,
                top: centerY + offset,
                child: _Line(
                  width: lineWidth,
                  thickness: 2.0,
                  color: aligned ? Colors.transparent : baseColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final double width;
  final double thickness;
  final Color color;
  const _Line({required this.width, required this.thickness, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: thickness,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}