import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen, non-dismissible block shown when the running build is older
/// than what the admin has published as required. This is its own tiny
/// [MaterialApp] so it can be run directly in place of the real app in
/// main(), before any of the app's own screens, navigation, or services
/// exist.
class UpdateRequiredScreen extends StatelessWidget {
  final String? storeUrl;
  const UpdateRequiredScreen({super.key, this.storeUrl});

  Future<void> _openStore() async {
    final url = storeUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasStoreUrl = storeUrl != null && storeUrl!.isNotEmpty;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF0B0B0B),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Update Required',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasStoreUrl
                          ? 'A new version of the app is available. Please update to continue.'
                          : 'This version of the app is no longer supported. Please install the latest version to continue.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (hasStoreUrl)
                      ElevatedButton(
                        onPressed: _openStore,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Text('Update Now'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
