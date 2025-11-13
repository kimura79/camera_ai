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
/// ℹ️ InfoIcon — Tooltip a schermo intero, centrato e chiudibile
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
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleTooltip() {
    if (_visible) {
      _hideTooltip();
    } else {
      _showTooltip();
    }
  }

  void _showTooltip() {
    _animController.forward();
    setState(() => _visible = true);
  }

  void _hideTooltip() {
    _animController.reverse();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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

        // 🔹 Tooltip fullscreen sopra tutto
        if (_visible)
          Positioned.fill(
            child: FadeTransition(
              opacity: _animController,
              child: Stack(
                children: [
                  // 🔸 Sfondo semi-trasparente (chiude se tocchi ovunque)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _hideTooltip,
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),

                  // 🔹 Tooltip centrato
                  Center(
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: screenWidth * 0.9,
                          minWidth: screenWidth * 0.8,
                          maxHeight: screenHeight * 0.5,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                widget.text,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.montserrat(
                                  fontSize: 15,
                                  height: 1.6,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextButton(
                                onPressed: _hideTooltip,
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      const Color(0xFF1A73E8),
                                ),
                                child: const Text(
                                  "Chiudi",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
