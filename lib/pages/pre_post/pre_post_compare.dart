import 'dart:io';
import 'package:flutter/material.dart';

class PrePostComparePage extends StatelessWidget {
  final File preOverlay;
  final File postOverlay;

  const PrePostComparePage({
    super.key,
    required this.preOverlay,
    required this.postOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Confronto Macchie")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Immagini affiancate
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        "Pre",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Image.file(preOverlay, fit: BoxFit.cover),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        "Post",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Image.file(postOverlay, fit: BoxFit.cover),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              "Confronto completato",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
