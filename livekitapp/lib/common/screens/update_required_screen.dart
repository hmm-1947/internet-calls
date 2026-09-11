import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Blocking screen shown when the backend reports this build is below the
/// admin-configured minimum version (HTTP 426 / websocket close 4010).
///
/// Two shapes, driven by whether [storeUrl] is passed:
/// - User app: pass the Play/App Store URL from
///   `/app-settings/version-check` (`user.android.store_url` /
///   `user.ios.store_url`) and this shows an "Update Now" button that opens
///   it.
/// - Listener app: the app is sideloaded and rebuilt/redistributed by the
///   admin directly (no store), so [storeUrl] should be omitted — this
///   shows a plain message telling the listener to get the new build from
///   the admin instead. [onRetry] is deliberately optional and not shown
///   for the listener case by default: reconnecting with the same old
///   binary will just be blocked again by the server until they actually
///   install the new build.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    this.requiredVersion,
    this.storeUrl,
    this.onRetry,
  });

  final String? requiredVersion;
  final String? storeUrl;
  final VoidCallback? onRetry;

  String _message() {
    final versionPart = requiredVersion != null
        ? ' (version $requiredVersion or newer is required)'
        : '';
    if (storeUrl != null) {
      return 'This app is no longer supported$versionPart. Please update from the store to continue.';
    }
    return 'This app is no longer supported$versionPart. Please get the latest build from the admin to continue.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: Color(0xFFE11D48),
                  size: 56,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Update required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _message(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD4E4FA),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (storeUrl != null) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => launchUrl(
                        Uri.parse(storeUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                      ),
                      child: const Text(
                        'UPDATE NOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ] else if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                    ),
                    child: const Text('I have the new build'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
