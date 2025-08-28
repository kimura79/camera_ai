import 'dart:io';
import 'package:flutter/material.dart';

class AnalysisPreview extends StatelessWidget {
  final String imagePath;

  const AnalysisPreview({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Anteprima Analisi")),
      body: Column(
        children: [
          Expanded(
            child: Image.file(File(imagePath)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // 👇 Qui invierai l'immagine al server Flask
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invio al server per analisi...")),
              );
            },
            child: const Text("Analizza"),
          ),
        ],
      ),
    );
  }
}