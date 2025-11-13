import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// 🧭 TooltipController (Compatibilità retroattiva)
/// ============================================================
/// Rimane definito per compatibilità ma non fa più nulla.
/// Ogni InfoIcon ora gestisce il proprio stato localmente.
class TooltipController extends ChangeNotifier {
  void show(Offset pos, String msg) {}
  void hide() {}
  bool get visible => false;
  Offset? get position => null;
  String? get text => null;
}

/// ============================================================
/// ℹ️ InfoIcon — Icona cliccabile che mostra il proprio tooltip
/// ============================================================
class InfoIcon extends StatefulWidget {
  final GlobalKey targetKey;
  final String text;
  final TooltipController controller; // mantenuto per compatibilità

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
      lowerBound: 0,
      upperBound: 1,
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
      alignment: Alignment.center,
      children: [
        // 🔹 Icona cliccabile
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

        // 🔹 Tooltip locale sopra la card
        if (_visible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideTooltip, // 🔸 Tap ovunque per chiudere
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: -85,
                    child: FadeTransition(
                      opacity: _animController,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: screenWidth * 0.9, // fino al 90% dello schermo
                            minWidth: screenWidth * 0.6, // almeno 60%
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
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
                            textAlign: TextAlign.left,
                            style: GoogleFonts.montserrat(
                              fontSize: 13.5,
                              height: 1.5,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // non serve più
  }
}
