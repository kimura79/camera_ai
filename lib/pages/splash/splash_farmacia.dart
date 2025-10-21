import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../home_page/home_farmacia.dart';

/// 💊 Splash Farmacia (stile Lovable)
class SplashFarmacia extends StatefulWidget {
  const SplashFarmacia({super.key});

  @override
  State<SplashFarmacia> createState() => _SplashFarmaciaState();
}

class _SplashFarmaciaState extends State<SplashFarmacia> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeFarmaciaPage()),
      );
    });
  }

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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_pharmacy,
                  color: Color(0xFF1A97F3), size: 90),
              const SizedBox(height: 30),
              Text(
                "Epidermys – Test Farmacie",
                style: GoogleFonts.montserrat(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A97F3),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Versione dedicata ai test in farmacia",
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(color: Color(0xFF1A97F3)),
            ],
          ),
        ),
      ),
    );
  }
}
