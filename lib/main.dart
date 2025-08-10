import 'package:flutter/material.dart';
import 'pages/home_page/home_page_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Test Fotocamera',
      theme: ThemeData.dark(),
      home: const HomePageWidget(),
    );
  }
}