import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// 🎯 TooltipController — Gestisce visibilità, testo e posizione
/// ============================================================
class TooltipController extends ChangeNotifier {
  Offset? position;
  String? text;

  void show(Offset pos, String msg) {
    position = pos;
    text = msg;
    notifyListeners();
  }

  void hide() {
    position = null;
    text = null;
    notifyListeners();
  }

  bool get visible => position != null && text != null;
}

/// ============================================================
/// ℹ️ InfoIcon — Icona cliccabile che mostra un tooltip
/// ============================================================
class InfoIcon extends StatelessWidget {
  final GlobalKey targetKey;
  final String text;
  final TooltipController controller;

  const InfoIcon({
    super.key,
    required this.targetKey,
    required this.text,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        final renderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final position = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;

          // 🔹 Tooltip centrato orizzontalmente sopra la card
          final offset = Offset(
            position.dx + size.width / 2 - 130, // centrato per width=260
            position.dy - 70, // sopra la card
          );

          controller.show(offset, text);
          debugPrint("ℹ️ Tooltip aperto per '$text'");
        } else {
          debugPrint("❌ targetKey non trovato per InfoIcon");
        }
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A73E8).withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.info_outline,
          size: 18,
          color: Color(0xFF1A73E8),
        ),
      ),
    );
  }
}

/// ============================================================
/// 💬 TooltipCard — Card flottante elegante con ombra
/// ============================================================
class TooltipCard extends StatelessWidget {
  final Offset position;
  final String text;

  const TooltipCard({
    super.key,
    required this.position,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
