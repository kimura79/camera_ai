import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// 🧭 TooltipController (Compatibilità retroattiva)
/// ============================================================
class TooltipController extends ChangeNotifier {
  void show(Offset pos, String msg) {}
  void hide() {}
  bool get visible => false;
  Offset? get position => null;
  String? get text => null;
}

/// ============================================================
///ℹ️ InfoIcon — Tooltip che si apre verso sinistra (visivamente)
/// ============================================================
class InfoIcon extends StatefulWidget {
  final GlobalKey targetKey;
  final String text;
  final TooltipController controller; // compatibilità

  const InfoIcon({
    super.key,
    required this.targetKey,
    required this.text,
    required this.controller,
  });

  @override
  State<InfoIcon> createState() => _InfoIconState();
}

class _InfoIconState extends State<InfoIcon>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleTooltip() {
    if (_visible) {
      _animController.reverse();
    } else {
      _animController.forward();
    }
    setState(() => _visible = !_visible);
  }

  void _hideTooltip() {
    if (_visible) {
      _animController.reverse();
      setState(() => _visible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 🔹 Icona "i" cliccabile
        InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: _toggleTooltip,
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
        ),

        // 🔹 Tooltip visibile + overlay per chiudere con tap ovunque
        if (_visible)
          Positioned.fill(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 🔸 Overlay cliccabile (chiude il tooltip ovunque tocchi)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideTooltip,
                  child: Container(color: Colors.transparent),
                ),

                // 🔹 Tooltip che si apre a sinistra della "i"
                Positioned(
                  top: -60, // leggero rialzo verticale
                  right: 10, // spostamento verso sinistra
                  child: FadeTransition(
                    opacity: _animController,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: screenWidth * 0.85,
                          minWidth: screenWidth * 0.7,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.text,
                          style: GoogleFonts.montserrat(
                            fontSize: 13.5,
                            height: 1.5,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ============================================================
/// 💬 TooltipCard (Compatibilità visiva, non più usata direttamente)
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
