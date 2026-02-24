import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The Logo / Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF9900CC).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  size: 72,
                  color: Color(0xFF9900CC),
                ),
              ),
              const SizedBox(height: 24),

              // App Title & Version
              const Text(
                '24-Player',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'v4.0.0 (Hi-Res Edition)',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),

              // The Mission Statement
              Text(
                'Built specifically for bit-perfect playback. No bloat, no upsampling, just pure 24-bit audio strictly for your IEMs.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 48),

              // GitHub Link
              TextButton.icon(
                onPressed: () => _launchUrl('https://github.com/zarzet/SpotiFLAC-Mobile'),
                icon: const Icon(Icons.code_rounded, size: 20),
                label: const Text('View Source Code'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9900CC),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}