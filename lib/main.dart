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

// 👉 Pagina camera aggiornata
import 'pages/home_page/home_page_widget.dart';
// 👉 Splash page Epidermys
import 'pages/camera_splash/camera_splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Richiesto da FlutterFlow + Web
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

  // FlutterFlow si aspetta questo metodo statico
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  /// TRUE = avvia direttamente la splash (Epidermys)
  /// FALSE = usa il router FlutterFlow (produzione)
  static const bool kLaunchDirectHome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);

    // 👇 reset jobs lato server allo startup
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

  // ==== Richiesti da flutter_flow_util.dart ====
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
  // =============================================

  @override
  Widget build(BuildContext context) {
    // 👉 Avvio diretto della pagina splash (non più camera)
    if (kLaunchDirectHome) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Custom Camera Component',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''),
          Locale('it', ''),
        ],
        theme: ThemeData(brightness: Brightness.light, useMaterial3: false),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: false),
        themeMode: _themeMode,
        home: const CameraSplashPage(), // 👈 Splash come entry point
      );
    }

    // 👉 Versione con router FlutterFlow
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Custom Camera Component',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('it', ''),
      ],
      theme: ThemeData(brightness: Brightness.light, useMaterial3: false),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: false),
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}
