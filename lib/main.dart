import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'flutter_flow/nav/nav.dart';
import 'index.dart';

// 👉 pagina camera
import 'pages/home_page/home_page_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // richiesto da FlutterFlow + web
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

  // 👇 FlutterFlow si aspetta questo
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = FlutterFlowTheme.themeMode;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;

  // 🔁 Toggle: TRUE = avvia direttamente HomePageWidget (test Codemagic / device)
  //            FALSE = usa il router FlutterFlow
  static const bool kLaunchDirectHome = true;

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
  void initState() {
    super.initState();
    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier); // inizializzato anche se non usato
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  @override
  Widget build(BuildContext context) {
    // 👉 Avvio diretto HomePage (test semplice: niente router)
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
        home: const HomePageWidget(),
      );
    }

    // 👉 Versione con router FlutterFlow (produzione)
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