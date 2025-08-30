import 'package:flutter/material.dart';

// importa le pagine reali
import '/pages/home_page/home_page_widget.dart';
import '/pages/pre_post/pre_post_widget.dart';
import '/pages/analyze_existing/analyze_existing_image_page.dart';

class CameraSplashPage extends StatelessWidget {
  const CameraSplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF0D1B2A);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Image.asset(
            'assets/images/epidermys_logo.png',
            height: 100,
          ),
          const SizedBox(height: 20),

          // Testo EPIDERMYS
          const Text(
            "EPIDERMYS",
            style: TextStyle(
              fontFamily: 'Helvetica',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: brandBlue,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 60),

          // Pulsanti centrali
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsante: Fotocamera
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HomePageWidget(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                  child: const Text("Fotocamera"),
                ),
                const SizedBox(height: 20),

                // 🔹 Pulsante: Analizza
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AnalyzeExistingImagePage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                  child: const Text("Analizza"),
                ),
                const SizedBox(height: 20),

                // Pulsante: Pre/Post
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PrePostWidget(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                  child: const Text("Pre/Post"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}