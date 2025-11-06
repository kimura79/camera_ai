import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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
  Map<String, dynamic>? resultData;
  File? overlayFile;

  final String serverUrl = "https://institution-fountain-plains-toe.trycloudflare.com";

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

  Future<void> _cancelJob() async {
    if (widget.jobId == null) return;
    try {
      await http.post(Uri.parse('$serverUrl/cancel_job/${widget.jobId}'));
    } catch (e) {
      debugPrint("⚠️ Errore cancellazione job: $e");
    }
  }

  Future<void> _cancelAllJobs() async {
    try {
      await http.post(Uri.parse('$serverUrl/cancel_all_jobs'));
    } catch (e) {
      debugPrint("⚠️ Errore cancellazione globale job: $e");
    }
  }

  Future<void> _loadResultData() async {
    try {
      final dir = await getTemporaryDirectory();
      final jsonFile = File("${dir.path}/result_farmacia.json");
      final overlay = File("${dir.path}/overlay_farmacia.png");

      if (await jsonFile.exists()) {
        final data = jsonDecode(await jsonFile.readAsString());
        setState(() => resultData = data);
      }
      if (await overlay.exists()) {
        setState(() => overlayFile = overlay);
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
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              "Invia risultati via email",
              style: GoogleFonts.montserrat(
                  fontSize: 18, fontWeight: FontWeight.w600),
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
                    onChanged: (v) =>
                        setStateDialog(() => autorizzazioneGDPR = v ?? false),
                    title: const Text(
                        "Autorizzo il trattamento dei dati personali ai sensi del GDPR"),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: autorizzazioneCommerciale,
                    onChanged: (v) => setStateDialog(
                        () => autorizzazioneCommerciale = v ?? false),
                    title: const Text(
                        "Acconsento a ricevere comunicazioni informative e commerciali"),
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
      content: Text("Compila tutti i campi e accetta il consenso GDPR."),
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
        });
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
          'POST', Uri.parse('$serverUrl/send_mail_farmacia'));
      req.fields['nome'] = nome;
      req.fields['email'] = email;
      req.fields['gdpr'] = gdpr.toString();
      req.fields['commerciale'] = commerciale.toString();
      if (widget.jobId != null) req.fields['job_id'] = widget.jobId!;
      if (resultData != null) {
        req.fields['result'] = jsonEncode(resultData);
      }
      if (overlayFile != null) {
        req.files.add(await http.MultipartFile.fromPath(
            'overlay', overlayFile!.path));
      }

      final resp = await req.send();
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("📧 Email inviata correttamente all’utente.")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("❌ Errore invio email: ${resp.statusCode}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Errore durante l’invio: $e")));
    }
  }

  // ==========================================================
  // UI PRINCIPALE
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    if (resultData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A73E8)),
        ),
      );
    }

    final double score = (resultData!["score_generale"] ?? 0.0).toDouble();
    final Map<String, dynamic> indici =
        Map<String, dynamic>.from(resultData!["indici"] ?? {});
    final String tipoPelle = resultData!["tipo_pelle"] ?? "Normale";
    final List<String> consigli =
        List<String>.from(resultData!["consigli"] ?? []);
    final double scorePercent = (score * 100).clamp(0, 100);

    return WillPopScope(
      onWillPop: () async {
        await _cancelJob();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A73E8),
          title: const Text("Analisi della Pelle"),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _cancelJob();
              Navigator.pop(context);
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ============================================================
// 🔹 Immagini cliccabili → apertura full-screen con swipe
// ============================================================
Row(
  children: [
    Expanded(
      child: GestureDetector(
        onTap: () {
          _showFullScreenImage(File(widget.imagePath), "Immagine originale");
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(widget.imagePath),
            height: 200,
            fit: BoxFit.cover,
          ),
        ),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: GestureDetector(
        onTap: () {
          if (overlayFile != null) {
            _showFullScreenImage(overlayFile!, "Overlay analisi");
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: overlayFile != null
              ? Image.file(overlayFile!, height: 200, fit: BoxFit.cover)
              : Container(
                  height: 200,
                  color: Colors.grey.shade200,
                  child: const Center(child: Text("Nessun overlay")),
                ),
        ),
      ),
    ),
  ],
),


              const SizedBox(height: 25),
              Text(
                "Punteggio Complessivo",
                style: GoogleFonts.montserrat(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                scorePercent.toStringAsFixed(0),
                style: GoogleFonts.montserrat(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A73E8)),
              ),
              Text("Salute della pelle",
                  style: GoogleFonts.montserrat(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54)),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4E9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tipoPelle,
                  style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE91E63)),
                ),
              ),

              const SizedBox(height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Analisi dei Domini Cutanei",
                    style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 10),
              ...indici.entries.map((entry) {
                final nome = entry.key;
                final valore = (entry.value as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(nome,
                                  style: GoogleFonts.montserrat(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87)),
                              Text(
                                  "${(valore * 100).toStringAsFixed(0)}%",
                                  style: GoogleFonts.montserrat(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green)),
                            ]),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                            value: valore,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(10),
                            backgroundColor: Colors.grey.shade300,
                            color: const Color(0xFF1A73E8)),
                      ]),
                );
              }).toList(),

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
  _buildAreaRow("Pori", "${(resultData!["aree_specifiche"]["pori_area_percent"] ?? 0).toStringAsFixed(1)} %"),
  _buildAreaRow("Rughe", "${(resultData!["aree_specifiche"]["rughe_lunghezza_mm"] ?? 0).toStringAsFixed(1)} mm"),
  _buildAreaRow("Macchie pigmentarie", "${(resultData!["aree_specifiche"]["macchie_area_percent"] ?? 0).toStringAsFixed(1)} %"),
  _buildAreaRow("Aree vascolari (Red Areas)", "${(resultData!["aree_specifiche"]["red_area_percent"] ?? 0).toStringAsFixed(1)} %"),
],


              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Raccomandazioni Personalizzate",
                    style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 4),
              Text("Formula skincare suggerita per te",
                  style: GoogleFonts.montserrat(
                      fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 12),
              _buildRefertiCard(consigli),
              const SizedBox(height: 40),

              // 🔹 Pulsanti finali
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1A73E8)),
                        minimumSize:
                            const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12))),
                    onPressed: () async {
                      await _cancelJob();
                      Navigator.pop(context);
                    },
                    child: Text("Nuova Analisi",
                        style: GoogleFonts.montserrat(
                            color: const Color(0xFF1A73E8),
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        minimumSize:
                            const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12))),
                    onPressed: _showSendMailDialog, // ✅ nuovo invio email
                    child: Text("Invia per Mail",
                        style: GoogleFonts.montserrat(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

    // ============================================================
  // 🔹 CARD CON I CONSIGLI (REFERTI)
  // ============================================================
  Widget _buildRefertiCard(List<String> consigli) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: consigli.map((txt) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "❗ ",
                  style: TextStyle(color: Colors.redAccent, fontSize: 18),
                ),
                Expanded(
                  child: Text(
                    txt,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
        Text(label,
            style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87)),
        Text(value,
            style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A73E8))),
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
