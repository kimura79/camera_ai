import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Classe helper per tutte le chiamate API al server Epidermys
class ApiService {
  // 🔗 URL base del tuo server DigitalOcean
  static const String baseUrl = "http://46.101.223.88:5000";

  /// Invio immagine per analisi
  static Future<Map<String, dynamic>?> uploadImageForAnalysis(
    File imageFile, {
    String analysisType = "macchie",
    String autore = "anonimo",
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/analyze");
      var request = http.MultipartRequest("POST", uri);

      // File immagine
      request.files.add(await http.MultipartFile.fromPath("file", imageFile.path));

      // Campi extra (analisi + autore, giudizio inizialmente 0)
      request.fields['analysis_type'] = analysisType;
      request.fields['autore'] = autore;
      request.fields['giudizio'] = "0"; // inizialmente senza giudizio

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return json.decode(body) as Map<String, dynamic>;
      } else {
        print("❌ Errore upload: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("❌ Eccezione uploadImageForAnalysis: $e");
      return null;
    }
  }

  /// Invio del giudizio medico (1–10) su una analisi già fatta
  static Future<bool> sendJudgement({
    required String filename,
    required int giudizio,
    String analysisType = "macchie",
    String autore = "anonimo",
  }) async {
    try {
      // 🔄 adesso usa l'endpoint /judge
      final uri = Uri.parse("$baseUrl/judge");
      var request = http.MultipartRequest("POST", uri);

      // File NON viene rimandato, mandiamo solo i campi
      request.fields['filename'] = filename;
      request.fields['analysis_type'] = analysisType;
      request.fields['autore'] = autore;
      request.fields['giudizio'] = giudizio.toString();

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        print("✅ Giudizio inviato: $body");
        return true;
      } else {
        print("❌ Errore invio giudizio: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("❌ Eccezione sendJudgement: $e");
      return false;
    }
  }
}
