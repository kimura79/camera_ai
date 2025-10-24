import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'flutter_flow/flutter_flow_util.dart';

class FFAppState extends ChangeNotifier {
  static FFAppState _instance = FFAppState._internal();

  factory FFAppState() {
    return _instance;
  }

  FFAppState._internal();

  static void reset() {
    _instance = FFAppState._internal();
  }

  /// ======================================================
  /// 🔹 INIZIALIZZAZIONE PERSISTENTE
  /// ======================================================
  Future initializePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _modalita = prefs.getString('modalita') ?? 'utente';
  }

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  /// ======================================================
  /// 🔹 VARIABILI ESISTENTI (non toccate)
  /// ======================================================
  bool _makePhoto = false;
  bool get makePhoto => _makePhoto;
  set makePhoto(bool value) {
    _makePhoto = value;
  }

  String _fileBase64 = '';
  String get fileBase64 => _fileBase64;
  set fileBase64(String value) {
    _fileBase64 = value;
  }

  /// ======================================================
  /// 🔹 NUOVA VARIABILE: MODALITÀ UTENTE
  /// ======================================================
  String _modalita = 'utente'; // può essere: 'medico', 'farmacia', 'utente'
  String get modalita => _modalita;

  Future<void> setModalita(String nuovaModalita) async {
    _modalita = nuovaModalita;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modalita', nuovaModalita);
    notifyListeners();
  }
}
