// ============================================================
// 🧠 AnalysisPharmaPage — Sezione iniziale aggiornata
// ============================================================

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/tooltip_info.dart';


class AnalysisPharmaPage extends StatefulWidget {
  final String imagePath;
  final String? jobId;

  const AnalysisPharmaPage({
    super.key,
    required this.imagePath,
    this.jobId,
  });

  @override
  State<AnalysisPharmaPage> createState() => _AnalysisPharmaPageState();
}

class _AnalysisPharmaPageState extends State<AnalysisPharmaPage> {
  // ============================================================
  // 🔹 VARIABILI PRINCIPALI
  // ============================================================
  Map<String, dynamic>? resultData;
  File? overlayFile;
  final TooltipController tooltip = TooltipController();

  // 🔹 URL del server AI (Cloudflare Tunnel attivo)
  // puoi sostituire con ai.epidermys.com se usi DNS dedicato
  final String serverUrl =
      "https://ray-stake-prediction-underground.trycloudflare.com";

  @override
  void initState() {
    super.initState();
    _loadResultData();
  }

  @override
  void dispose() {
    _cancelAllJobs();
    super.dispose();
  }

  // ============================================================
  // ❌ CANCELLAZIONE JOB SINGOLO
  // ============================================================
  Future<void> _cancelJob() async {
    if (widget.jobId == null) return;
    try {
      final uri = Uri.parse('$serverUrl/cancel_job/${widget.jobId}');
      final res = await http.post(uri);
      if (res.statusCode == 200) {
        debugPrint("🧹 Job ${widget.jobId} annullato correttamente.");
      } else {
        debugPrint("⚠️ Errore durante cancellazione job (${res.statusCode})");
      }
    } catch (e) {
      debugPrint("❌ Errore cancellazione job: $e");
    }
  }

  // ============================================================
  // ❌ CANCELLAZIONE DI TUTTI I JOB ATTIVI
  // ============================================================
  Future<void> _cancelAllJobs() async {
    try {
      final uri = Uri.parse('$serverUrl/cancel_all_jobs');
      final res = await http.post(uri);
      if (res.statusCode == 200) {
        debugPrint("🧹 Tutti i job attivi cancellati correttamente.");
      } else {
        debugPrint("⚠️ Errore cancellazione globale job (${res.statusCode})");
      }
    } catch (e) {
      debugPrint("❌ Errore cancellazione globale job: $e");
    }
  }

// ============================================================
// 🧹 CANCELLA SOLO FILE LOCALI (overlay e JSON in RAM)
// ============================================================
Future<void> _clearOldResults() async {
  try {
    final dir = await getTemporaryDirectory();
    final jsonFile = File("${dir.path}/result_farmacia.json");
    final overlay = File("${dir.path}/overlay_farmacia.png");

    if (await jsonFile.exists()) {
      await jsonFile.delete();
      debugPrint("🗑️ File result_farmacia.json eliminato.");
    }
    if (await overlay.exists()) {
      await overlay.delete();
      debugPrint("🗑️ File overlay_farmacia.png eliminato.");
    }

    setState(() {
      overlayFile = null;
      resultData = null;
    });
  } catch (e) {
    debugPrint("❌ Errore cancellazione file locali: $e");
  }
}


  // ============================================================
  // 📂 CARICAMENTO RISULTATI ANALISI + OVERLAY
  // ============================================================
  Future<void> _loadResultData() async {
    try {
      final dir = await getTemporaryDirectory();
      final jsonFile = File("${dir.path}/result_farmacia.json");
      final overlay = File("${dir.path}/overlay_farmacia.png");

      if (await jsonFile.exists()) {
        final jsonContent = await jsonFile.readAsString();
        final data = jsonDecode(jsonContent);
        setState(() => resultData = data);
        debugPrint("✅ Dati analisi caricati con successo (${jsonFile.path})");
      } else {
        debugPrint("⚠️ Nessun file 'result_farmacia.json' trovato.");
      }

      if (await overlay.exists()) {
        setState(() => overlayFile = overlay);
        debugPrint("🖼️ Overlay caricato correttamente (${overlay.path})");
      } else {
        debugPrint("⚠️ Nessun overlay trovato in ${overlay.path}");
      }
    } catch (e) {
      debugPrint("❌ Errore caricamento dati farmacia: $e");
    }
  }

// ==========================================================
// 📨 INVIO EMAIL
// ==========================================================
Future<void> _showSendMailDialog() async {
  final TextEditingController nomeCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  bool autorizzazioneGDPR = false;
  bool autorizzazioneCommerciale = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              "Invia risultati via email",
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(labelText: "Nome"),
                  ),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: "Email"),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: autorizzazioneGDPR,
                    onChanged: (v) => setStateDialog(
                      () => autorizzazioneGDPR = v ?? false,
                    ),
                    title: const Text(
                      "Autorizzo il trattamento dei dati personali ai sensi del GDPR",
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: autorizzazioneCommerciale,
                    onChanged: (v) => setStateDialog(
                      () => autorizzazioneCommerciale = v ?? false,
                    ),
                    title: const Text(
                      "Acconsento a ricevere comunicazioni informative e commerciali",
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annulla"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nomeCtrl.text.isEmpty ||
                      emailCtrl.text.isEmpty ||
                      !autorizzazioneGDPR) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Compila tutti i campi e accetta il consenso GDPR.",
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  await _sendResultsByEmail(
                    nomeCtrl.text,
                    emailCtrl.text,
                    autorizzazioneGDPR,
                    autorizzazioneCommerciale,
                  );
                },
                child: const Text("Invia"),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _sendResultsByEmail(
  String nome,
  String email,
  bool gdpr,
  bool commerciale,
) async {
  try {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$serverUrl/send_mail_farmacia'),
    );
    req.fields['nome'] = nome;
    req.fields['email'] = email;
    req.fields['gdpr'] = gdpr.toString();
    req.fields['commerciale'] = commerciale.toString();

    if (widget.jobId != null) {
      req.fields['job_id'] = widget.jobId!;
    }

    if (resultData != null) {
      req.fields['result'] = jsonEncode(resultData);
    }

    if (overlayFile != null) {
      req.files.add(
        await http.MultipartFile.fromPath('overlay', overlayFile!.path),
      );
    }

    final resp = await req.send();
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📧 Email inviata correttamente all’utente."),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Errore invio email: ${resp.statusCode}"),
        ),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("❌ Errore durante l’invio: $e"),
      ),
    );
  }
}


// ==========================================================
// UI PRINCIPALE — Versione Lovable.dev aggiornata
// ==========================================================
@override
Widget build(BuildContext context) {
  if (resultData == null) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: const Center(
        child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
      ),
    );
  }

  final double score = (resultData!["score_generale"] ?? 0.0).toDouble();
  final Map<String, dynamic> indici =
      Map<String, dynamic>.from(resultData!["indici"] ?? {});
  final double scorePercent = (score * 100).clamp(0, 100);

  // 🔹 Lettura blocco "Referti" dal server Python
  final Map<String, dynamic> referti =
      Map<String, dynamic>.from(resultData!["Referti"] ?? {});

  final String tipoPelle = referti["Tipo_pelle"] ?? "Normale / Equilibrata";
  final String dominante = referti["Dominante"] ?? "-";
  final String secondario = referti["Secondario"] ?? "-";
  final List<String> consigli =
      List<String>.from(referti["Consigli"] ?? []);

  return WillPopScope(
    onWillPop: () async {
      await _cancelJob();
      return true;
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Analisi della Pelle",
          style: GoogleFonts.montserrat(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
leading: IconButton(
  icon: const Icon(Icons.arrow_back, color: Colors.black87),
  onPressed: () async {
    await _cancelJob();
    await _clearOldResults(); // ✅ cancella overlay in RAM solo qui
    Navigator.pop(context);
  },
),
      ),

// ============================================================
// 🩵 BODY — Layout Lovable.dev + Tooltip Flottante
// ============================================================
body: GestureDetector(
  onTap: () => tooltip.hide(),
  child: Stack(
    children: [
      SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ============================================================
            // 🖼️ OVERLAY ANALISI — Anteprima tappabile (Lovable style)
            // ============================================================
            GestureDetector(
              onTap: () {
                if (overlayFile != null) {
                  _showFullScreenImage(overlayFile!, "Overlay analisi");
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: overlayFile != null
                    ? Image.file(
                        overlayFile!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        height: 250,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Text(
                            "Nessun overlay disponibile",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 25),

            // ============================================================
            // 🟢 RISULTATO COMPLESSIVO — Gauge circolare
            // ============================================================
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Risultato Complessivo",
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: scorePercent / 100,
                          strokeWidth: 12,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _colore(scorePercent / 100),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            scorePercent.toStringAsFixed(0),
                            style: GoogleFonts.montserrat(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: _colore(scorePercent / 100),
                            ),
                          ),
                          Text(
                            "/ 100",
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Salute della Pelle",
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _colore(scorePercent / 100).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      giudizio(scorePercent / 100),
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _colore(scorePercent / 100),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tipoPelle,
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ============================================================
            // 📈 PUNTO DI FORZA / DA MIGLIORARE
            // ============================================================
            Builder(
              builder: (context) {
                if (indici.isEmpty) return const SizedBox.shrink();

                final Map<String, double> baseIndici = {
                  "Elasticità": (indici["Elasticità"] ?? 0.0).toDouble(),
                  "Texture": (indici["Texture"] ?? 0.0).toDouble(),
                  "Idratazione": (indici["Idratazione"] ?? 0.0).toDouble(),
                  "Chiarezza": (indici["Chiarezza"] ?? 0.0).toDouble(),
                };

                final sorted = baseIndici.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                final best = sorted.first;
                final worst = sorted.last;

                return Column(
                  children: [
                    _buildInfoCard(
                      titolo: "Punto di Forza",
                      sottotitolo: best.key,
                      descrizione:
                          "Eccellente con ${(best.value * 100).toStringAsFixed(0)}%",
                      colore: const Color(0xFFB7EFC5),
                      icona: Icons.trending_up,
                      positivo: true,
                    ),
                    const SizedBox(height: 10),
                    _buildInfoCard(
                      titolo: "Da Migliorare",
                      sottotitolo: worst.key,
                      descrizione:
                          "Richiede attenzione (${(worst.value * 100).toStringAsFixed(0)}%)",
                      colore: const Color(0xFFFAD0D0),
                      icona: Icons.trending_down,
                      positivo: false,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 30),

            // ============================================================
            // 📊 ANALISI DETTAGLIATA + PARAMETRI
            // ============================================================
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Analisi Dettagliata per Parametro",
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildDetailedSection(indici, resultData!, consigli),

            // ============================================================
// 🔹 SEZIONE ESTENSIONI AREE SPECIFICHE
// ============================================================
if (resultData!["aree_specifiche"] != null) ...[
  const SizedBox(height: 30),
  Align(
    alignment: Alignment.centerLeft,
    child: Text(
      "Estensioni Aree Specifiche",
      style: GoogleFonts.montserrat(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
  ),
  const SizedBox(height: 10),
  _buildAreaRow(
    "Pori",
    "${(resultData!["aree_specifiche"]["pori_area_percent"] ?? 0).toStringAsFixed(1)} %",
  ),
  _buildAreaRow(
    "Rughe",
    "${(resultData!["aree_specifiche"]["rughe_lunghezza_mm"] ?? 0).toStringAsFixed(1)} mm",
  ),
  _buildAreaRow(
    "Macchie pigmentarie",
    "${(resultData!["aree_specifiche"]["macchie_area_percent"] ?? 0).toStringAsFixed(1)} %",
  ),
  _buildAreaRow(
    "Aree vascolari (Red Areas)",
    "${(resultData!["aree_specifiche"]["red_area_percent"] ?? 0).toStringAsFixed(1)} %",
  ),
],


            const SizedBox(height: 40),

            // ============================================================
            // 💊 RACCOMANDAZIONI PERSONALIZZATE + REFERTI
            // ============================================================
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Raccomandazioni Personalizzate",
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Formula skincare suggerita per te",
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            _buildRefertiCard(consigli),

            const SizedBox(height: 40),

            // ============================================================
            // 🔹 PULSANTI FINALI — Nuova analisi / Invia per mail
            // ============================================================
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1A73E8)),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await _cancelJob();
                      Navigator.pop(context);
                    },
                    child: Text(
                      "Nuova Analisi",
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF1A73E8),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _showSendMailDialog,
                    child: Text(
                      "Invia per Mail",
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),

      // ============================================================
      // 🟦 TOOLTIP FLOTTANTE
      // ============================================================
      if (tooltip.visible)
        TooltipCard(
          position: tooltip.position!,
          text: tooltip.text!,
        ),
    ],
  ),
),
), // 👈 chiude Scaffold
); // 👈 chiude WillPopScope
} // 👈 chiude build()






// ============================================================
// 🎨 Giudizio e Colori dinamici (Lovable.dev)
// ============================================================
String giudizio(double v) {
  if (v < 0.45) return "Scarso";
  if (v < 0.70) return "Sufficiente";
  return "Buono";
}

Color _colore(double v) {
  if (v < 0.45) return const Color(0xFFE53935);
  if (v < 0.70) return const Color(0xFFFFB300);
  return const Color(0xFF43A047);
}

// 🎨 Colori invertiti solo per Stress Cutaneo (0 = rilassato → verde)
Color _coloreStress(double v) {
  if (v < 0.45) return const Color(0xFF43A047); // verde
  if (v < 0.70) return const Color(0xFFFFB300); // giallo
  return const Color(0xFFE53935); // rosso
}

// 🧘‍♀️ Giudizio invertito solo per Stress Cutaneo
String giudizioStress(double v) {
  if (v < 0.45) return "Buono"; // basso stress = buono
  if (v < 0.70) return "Sufficiente"; // medio stress
  return "Scarso"; // alto stress = scarso
}

// ============================================================
// 🔹 CARD “Punto di Forza” e “Da Migliorare” — Stile Lovable.dev
// ============================================================
Widget _buildInfoCard({
  required String titolo,
  required String sottotitolo,
  required String descrizione,
  required Color colore,
  required IconData icona,
  required bool positivo,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.symmetric(vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
      border: Border.all(color: colore.withOpacity(0.4), width: 1.2),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colore.withOpacity(0.25),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icona,
            color: positivo ? Colors.green[700] : Colors.red[700],
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titolo,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: positivo ? Colors.green[700] : Colors.red[700],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sottotitolo,
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                descrizione,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}


// ============================================================
// 🔹 CARD PARAMETRICA — Barre, giudizio e supporto Età Biologica
// ============================================================
Widget _buildParamCard(
  String titolo,
  double valore, {
  double? etaReale,
  Color? colorePersonalizzato,
  String Function(double)? giudizioPersonalizzato,
}) {
  final colore = colorePersonalizzato ?? _colore(valore);
  final String testoGiudizio = giudizioPersonalizzato != null
      ? giudizioPersonalizzato(valore)
      : giudizio(valore);

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colore.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titolo,
              style: GoogleFonts.montserrat(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Text(
              "${(valore * 100).toStringAsFixed(0)} / 100",
              style: GoogleFonts.montserrat(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colore,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: valore,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(colore),
        ),
        if (etaReale != null) ...[
          const SizedBox(height: 6),
          Text(
            "Età stimata: ${etaReale.toStringAsFixed(0)} anni",
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          testoGiudizio,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            color: colore,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// 🔹 CARD PARAMETRICA con ICONA INFO + Tooltip
// ============================================================
Widget _buildParamCardWithInfo({
  required GlobalKey key,
  required String titolo,
  required double valore,
  required String tooltipText,
  Color? colorePersonalizzato,
  String Function(double)? giudizioPersonalizzato,
}) {
  final colore = colorePersonalizzato ?? _colore(valore);
  final testoGiudizio = giudizioPersonalizzato != null
      ? giudizioPersonalizzato(valore)
      : giudizio(valore);

  return Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colore.withOpacity(0.12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titolo,
              style: GoogleFonts.montserrat(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Row(
              children: [
                Text(
                  "${(valore * 100).toStringAsFixed(0)} / 100",
                  style: GoogleFonts.montserrat(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colore,
                  ),
                ),
                const SizedBox(width: 8),
                InfoIcon(
                  targetKey: key,
                  controller: tooltip,
                  text: tooltipText,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: valore,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(colore),
        ),
        const SizedBox(height: 5),
        Text(
          testoGiudizio,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colore,
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// 🔹 SEZIONE INDICI CLINICI (4 BASE) + PARAMETRI AVANZATI (4)
// ============================================================
Widget _buildDetailedSection(
  Map<String, dynamic> indici,
  Map<String, dynamic> resultData,
  List<String> consigli,
) {
  // 🔹 Marketing + avanzati
  final double vitalita = ((resultData["marketing"]?["Vitalità"] ?? 0.0).toDouble()).clamp(0.0, 1.0);
  final double glow = ((resultData["marketing"]?["Glow Naturale"] ?? 0.0).toDouble()).clamp(0.0, 1.0);
  final double stress = ((resultData["marketing"]?["Stress Cutaneo"] ?? 0.0).toDouble()).clamp(0.0, 1.0);
  final double giovinezza = ((resultData["marketing"]?["Indice di Giovinezza"] ?? 0.0).toDouble()).clamp(0.0, 1.0);

  // CHIAVI PER TOOLTIP
  final keyElasticita = GlobalKey();
  final keyTexture = GlobalKey();
  final keyIdratazione = GlobalKey();
  final keyChiarezza = GlobalKey();

  final keyVitalita = GlobalKey();
  final keyGlow = GlobalKey();
  final keyStress = GlobalKey();
  final keyGiovinezza = GlobalKey();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      // ============================================================
      // 🔹 4 INDICI CLINICI BASE
      // ============================================================

      _buildParamCardWithInfo(
        key: keyElasticita,
        titolo: "Elasticità",
        valore: indici["Elasticità"] ?? 0.0,
        tooltipText:
            "Indica quanto la pelle resiste alla formazione di rughe e microrughe.",
      ),

      _buildParamCardWithInfo(
        key: keyTexture,
        titolo: "Texture",
        valore: indici["Texture"] ?? 0.0,
        tooltipText:
            "Misura la regolarità della grana della pelle e la presenza di microrilievi.",
      ),

      _buildParamCardWithInfo(
        key: keyIdratazione,
        titolo: "Idratazione",
        valore: indici["Idratazione"] ?? 0.0,
        tooltipText:
            "Indica quanta acqua e luminosità naturale trattiene la pelle.",
      ),

      _buildParamCardWithInfo(
        key: keyChiarezza,
        titolo: "Chiarezza",
        valore: indici["Chiarezza"] ?? 0.0,
        tooltipText:
            "Misura quanto il colore della pelle è uniforme (macchie, rossori, discromie).",
      ),

      const SizedBox(height: 35),

      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          "Parametri Avanzati",
          style: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      const SizedBox(height: 14),

      // ============================================================
      // 🔹 4 INDICI AVANZATI
      // ============================================================

      _buildParamCardWithInfo(
        key: keyVitalita,
        titolo: "Vitalità Cutanea",
        valore: vitalita,
        tooltipText:
            "Indica la vitalità generale della pelle: energia, ossigenazione e freschezza.",
      ),

      _buildParamCardWithInfo(
        key: keyGlow,
        titolo: "Glow Naturale",
        valore: glow,
        tooltipText:
            "Misura la luminosità naturale e il riflesso sano della pelle.",
      ),

      _buildParamCardWithInfo(
        key: keyStress,
        titolo: "Stress Cutaneo",
        valore: stress,
        colorePersonalizzato: _coloreStress(stress),
        giudizioPersonalizzato: giudizioStress,
        tooltipText:
            "Valuta quanto la pelle è stressata (rossori, infiammazione, sensibilità).",
      ),

      _buildParamCardWithInfo(
        key: keyGiovinezza,
        titolo: "Indice di Giovinezza",
        valore: giovinezza,
        tooltipText:
            "Indica quanto la pelle appare giovane rispetto alla sua età biologica.",
      ),

      const SizedBox(height: 30),
    ],
  );
}

// ============================================================
// 🔹 CARD CON I CONSIGLI (REFERTI CLINICI — ❕STILE iOS SOFT)
// ============================================================
Widget _buildRefertiCard(List<String> consigli) {
  if (consigli.isEmpty) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        "Nessun referto disponibile per questa analisi.",
        style: GoogleFonts.montserrat(
          fontSize: 15,
          color: Colors.black54,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // 🔹 Etichette cliniche standard
  final List<String> etichette = [
    "Stato generale della pelle",
    "Obiettivi dermocosmetici",
    "Principi attivi consigliati",
    "Routine suggerita",
    "Consigli professionali",
  ];

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(consigli.length, (i) {
        final titolo = i < etichette.length ? etichette[i] : "Dettaglio ${i + 1}";
        final testo = consigli[i]
            .replaceAll(RegExp(r'^\*\*.*?\*\*\n?'), '') // rimuove eventuali doppie intestazioni "**Titolo**"
            .trim();

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
               padding: const EdgeInsets.only(top: 4, right: 8),
               child: Text(
               "❗", // 🔴 Punto esclamativo rosso
               style: const TextStyle(
                fontSize: 22,   // puoi regolare (es. 20–24)
                height: 1.3,    // allineamento verticale
                ),
               ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titolo,
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      testo,
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    ),
  );
}

// ============================================================
// 🔹 RIGA VALORI “AREE SPECIFICHE”
// ============================================================
Widget _buildAreaRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A73E8),
          ),
        ),
      ],
    ),
  );
}



  // ============================================================
  // 🖼️ VIEWER FULL-SCREEN CON SWIPE, ZOOM E CHIUSURA
  // ============================================================
  void _showFullScreenImage(File imageFile, String titolo) {
    final List<Map<String, dynamic>> immagini = [
      {"file": File(widget.imagePath), "titolo": "Immagine originale"},
      if (overlayFile != null)
        {"file": overlayFile!, "titolo": "Overlay analisi"},
    ];

    int initialPage =
        immagini.indexWhere((img) => img["file"].path == imageFile.path);
    if (initialPage < 0) initialPage = 0;

    final PageController controller = PageController(initialPage: initialPage);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                // 🔹 Swipe destra/sinistra
                PageView.builder(
                  controller: controller,
                  itemCount: immagini.length,
                  itemBuilder: (context, index) {
                    final current = immagini[index];
                    return Center(
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 5.0,
                        child:
                            Image.file(current["file"], fit: BoxFit.contain),
                      ),
                    );
                  },
                ),

              // 🔹 Titolo dinamico
Positioned(
  top: 20,
  left: 20,
  child: AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      int index = controller.hasClients
          ? controller.page?.round() ?? initialPage
          : initialPage;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          immagini[index]["titolo"],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    },
  ),
),


                // 🔹 Bottone chiudi
                Positioned(
                  top: 20,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
