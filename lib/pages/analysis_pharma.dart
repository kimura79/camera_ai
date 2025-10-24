// 📄 lib/pages/analysis_pharma.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnalysisPharmaPage extends StatelessWidget {
  final String imagePath;
  final double score;
  final Map<String, double> indici;
  final List<String> consigli;
  final String tipoPelle;

  const AnalysisPharmaPage({
    super.key,
    required this.imagePath,
    this.score = 82,
    this.indici = const {
      "Idratazione": 0.82,
      "Texture": 0.90,
      "Chiarezza": 0.82,
      "Elasticità": 0.81,
    },
    this.consigli = const [
      "Usa un siero con acido ialuronico per aumentare l’idratazione",
      "Applica una crema con vitamina C per migliorare la luminosità",
      "Utilizza un prodotto con retinolo per migliorare la texture",
      "Non dimenticare la protezione solare SPF 50+ ogni giorno",
      "Considera l’uso di niacinamide per uniformare il tono della pelle",
    ],
    this.tipoPelle = "Grassa",
  });
