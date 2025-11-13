import 'package:flutter/material.dart';

/// Stato del tooltip (dove mostrarlo e cosa mostrare)
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

/// Card flottante
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
      top: position.dy - 70, // si posiziona sopra la card
      child: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.3),
          ),
        ),
      ),
    );
  }
}

/// Icona "i" che mostra il tooltip
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
      onTap: () {
        final box = targetKey.currentContext!.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset.zero);
        controller.show(pos, text);
      },
      child: const Icon(Icons.info_outline, color: Colors.grey, size: 20),
    );
  }
}
