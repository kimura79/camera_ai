// lib/pages/pre_post/pre_post_widget.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:custom_camera_component/pages/analysis_preview.dart';
import 'package:custom_camera_component/pages/distanza_cm_overlay.dart';
import 'package:custom_camera_component/pages/level_guide.dart';

class PrePostWidget extends StatefulWidget {
  final File guideImage; // immagine PRE come overlay guida

  const PrePostWidget({super.key, required this.guideImage});

  @override
  State<PrePostWidget> createState() => _PrePostWidgetState();
}