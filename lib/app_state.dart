// 📄 lib/flutter_flow/ff_app_state.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FFAppState extends ChangeNotifier {
  // ======================================================
  // 🔹 SINGLETON
  // ======================================================
  static FFAppState _instance = FFAppState._internal();
  factory FFAppState() => _instance;
  FFAppState._internal();

  static void reset() {
    _instance = FFAppState._internal();
  }

  // ======================================================
  // 🔹 INIZIALIZZAZIONE PERSISTENTE
  // ======================================================
  Future<void> initializePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _modalita = prefs.getString('modalita') ?? 'utente';
    _makePhoto = prefs.getBool('makePhoto') ?? false;
    _fileBase64 = prefs.getString('fileBase64') ?? '';
  }

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  // ======================================================
  // 🔹 VARIABILI ESISTENTI
  // ======================================================
  bool _makePhoto = false;
  bool get makePhoto => _makePhoto;
  set makePhoto(bool value) {
    _makePhoto = value;
    _saveBool('makePhoto', value);
    notifyListeners();
  }

  String _fileBase64 = '';
  String get fileBase64 => _fileBase64;
  set fileBase64(String value) {
    _fileBase64 = value;
    _saveString('fileBase64', value);
    notifyListeners();
  }

  // ======================================================
  // 🔹 NUOVA VARIABILE: MODALITÀ UTENTE
  // ======================================================
  String _modalita = 'utente'; // può essere: 'medico', 'farmacia', 'utente'
  String get modalita => _modalita;

  Future<void> setModalita(String nuovaModalita) async {
    _modalita = nuovaModalita;
    await _saveString('modalita', nuovaModalita);
    notifyListeners();
  }

  // ======================================================
  // 🔹 METODI PRIVATI DI SUPPORTO
  // ======================================================
  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
