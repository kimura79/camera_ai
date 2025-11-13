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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final size = box.size;
          // 🔹 Tooltip centrato orizzontalmente sopra l’icona
          final offset = Offset(
            position.dx + size.width / 2 - 130, // centrato rispetto al width=260
            position.dy - 60, // sopra la card
          );
          controller.show(offset, text);
        }
      },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.info_outline,
          size: 16,
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
    );
  }
}
