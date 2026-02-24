import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DonatePage extends StatelessWidget {
  const DonatePage({super.key});

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Signature Purple Icon
              const Icon(
                Icons.headphones_rounded,
                size: 80,
                color: Color(0xFF9900CC),
              ),
              const SizedBox(height: 24),

              // The Message
              const Text(
                "Just enjoy the app!",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "No donations needed. If you like 24-Player, just drop a follow to support the development.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 48),

              // Instagram Button
              ElevatedButton.icon(
                onPressed: () => _launchUrl('https://instagram.com/nixant_20'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Follow on Instagram'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // GitHub Button
              OutlinedButton.icon(
                // Using the zarzet github link you provided earlier
                onPressed: () => _launchUrl('https://github.com/nishant-404'),
                icon: const Icon(Icons.code_rounded),
                label: const Text('Follow on GitHub'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(220, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}