import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/api_client.dart';

/// Result of a version check that means the running build must be updated
/// before the app can be used further. `storeUrl` is set for the user app
/// (which is store-distributed); it's always null for the listener app,
/// which is sideloaded and has nothing to redirect to.
class AppVersionBlock {
  final String? storeUrl;
  const AppVersionBlock({this.storeUrl});
}

/// Talks to `/app-settings/version-check` and decides whether the currently
/// running build is behind what the admin has published as the latest
/// version. Deliberately fails open: any error (offline, timeout, bad
/// response, admin hasn't set a version yet) resolves to "not blocked" —
/// this check must never be able to lock someone out of the app on its own
/// due to a network hiccup.
class AppVersionService {
  static List<int> _parts(String version) => RegExp(r'\d+')
      .allMatches(version)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  static bool _isOutdated(String? current, String? required) {
    if (required == null || required.isEmpty) return false;
    if (current == null || current.isEmpty) return true;
    final c = _parts(current);
    final r = _parts(required);
    final len = c.length > r.length ? c.length : r.length;
    for (var i = 0; i < len; i++) {
      final cv = i < c.length ? c[i] : 0;
      final rv = i < r.length ? r[i] : 0;
      if (cv != rv) return cv < rv;
    }
    return false;
  }

  static Future<Map<String, dynamic>?> _fetch() async {
    try {
      final response = await ApiClient().get(
        ApiConstants.appVersionCheck,
        timeout: const Duration(seconds: 6),
      );
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The listener app is sideloaded, so it only gets a required version
  /// number — no store link to offer.
  static Future<AppVersionBlock?> checkForListener() async {
    final data = await _fetch();
    if (data == null) return null;
    final required = data['listener']?['latest_version'] as String?;
    final info = await PackageInfo.fromPlatform();
    if (_isOutdated(info.version, required)) {
      return const AppVersionBlock();
    }
    return null;
  }

  /// The user app is distributed through the stores, so a block also comes
  /// with the right store URL for the platform it's running on.
  static Future<AppVersionBlock?> checkForUser() async {
    final data = await _fetch();
    if (data == null) return null;
    final platformKey = Platform.isIOS ? 'ios' : 'android';
    final platformData = data['user']?[platformKey] as Map<String, dynamic>?;
    final required = platformData?['latest_version'] as String?;
    final storeUrl = platformData?['store_url'] as String?;
    final info = await PackageInfo.fromPlatform();
    if (_isOutdated(info.version, required)) {
      return AppVersionBlock(storeUrl: storeUrl);
    }
    return null;
  }
}
