import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

// FlutterFlow
import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/nav/nav.dart';
import 'index.dart';

// 👉 Splash test
import 'pages/splash/splash_farmacia.dart';
import 'pages/splash/splash_user.dart';

// 👉 Splash originale (produzione medici)
import 'pages/camera_splash/camera_splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoRouter.optionURLReflectsImperativeAPIs = true;
  usePathUrlStrategy();

  await FlutterFlowTheme.initialize();

  final appState = FFAppState();
  await appState.initializePersistedState();

  runApp(
    ChangeNotifierProvider(
      create: (context) => appState,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = FlutterFlowTheme.themeMode;
  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    _resetJobsOnStartup();
  }

  Future<void> _resetJobsOnStartup() async {
    try {
      final url = Uri.parse("http://46.101.223.88:5000/cancel_all_jobs");
      final resp = await http.post(url);
      if (resp.statusCode == 200) {
        debugPrint("🧹 Tutti i job cancellati allo startup");
      } else {
        debugPrint("⚠️ Errore reset job: ${resp.statusCode}");
      }
    } catch (e) {
      debugPrint("⚠️ Errore reset job allo startup: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }

  List<String> getRouteStack() => _router
      .routerDelegate.currentConfiguration.matches
      .map((e) => getRoute(e))
      .toList();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Epidermys',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('it', ''),
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
        fontFamily: 'Montserrat',
      ),
      home: const UserTypeSelectorPage(), // 👈 schermata iniziale di scelta
    );
  }
}

/// ============================================================
/// 🔹 Schermata di scelta tipo utente (mostrata sempre all’avvio)
/// ============================================================
class UserTypeSelectorPage extends StatelessWidget {
  const UserTypeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE9F6FF), Color(0xFFCDEBFA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔹 Logo Epidermys
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Image.asset(
                    'assets/images/epidermys_logo.png', // assicurati del path esatto
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  "Scegli la modalità di utilizzo",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A97F3),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // 🔹 Pulsante Medico
                _buildButton(
                  context,
                  label: "👨‍⚕️ Modalità Medico",
                  color: Colors.indigo,
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CameraSplashPage(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // 🔹 Pulsante Farmacia
                _buildButton(
                  context,
                  label: "💊 Modalità Farmacia",
                  color: Colors.blueAccent,
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SplashFarmacia(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // 🔹 Pulsante User
                _buildButton(
                  context,
                  label: "👤 Modalità Utente Privato",
                  color: Colors.teal,
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SplashUser(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context,
      {required String label,
      required Color color,
      required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 5,
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}
