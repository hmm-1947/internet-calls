import 'package:package_info_plus/package_info_plus.dart';

/// Holds the installed build's version string (e.g. "2.10.0") for the
/// lifetime of the process. Loaded once during app startup, before any
/// network call is made, so `ApiClient` and `ChatSocketService` can read it
/// synchronously without threading it through every call site.
///
/// The backend's `is_outdated()` treats a missing version as outdated the
/// moment an admin sets a required version, so [current] must be populated
/// before login/session-check/websocket-connect are attempted.
class AppVersion {
  AppVersion._();

  static String? _current;

  /// The installed app's version (e.g. "2.10.0"), or null if [load] hasn't
  /// completed yet. Callers that skip [load] will simply be treated by the
  /// backend as running an unknown/outdated build once a minimum version is
  /// configured — same as any pre-versioning install.
  static String? get current => _current;

  /// Reads the version from the platform (Android/iOS build metadata).
  /// Safe to call multiple times; only the first call does any work.
  static Future<void> load() async {
    if (_current != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _current = info.version;
    } catch (_) {
      // Leave _current null; requests will go out without the header and
      // the backend will treat this build as outdated once a minimum
      // version is configured, same as it would for a build predating this
      // check entirely.
    }
  }
}

/// Dart port of `backend/app/utils/versioning.py::is_outdated`. Numeric-tuple
/// comparison of plain "major.minor.patch"-style version strings — no
/// pre-release/build-metadata handling, matching the server's own comment
/// that these builds never use anything fancier.
///
/// Needed client-side only for the user app: unlike the listener app, the
/// backend never force-blocks the user app (it's store-distributed, so a
/// store redirect is the right nudge, not a hard 426 on every request) —
/// see `app_settings.py::get_version_check`. So the user app has to do this
/// comparison itself against `/app-settings/version-check` to decide
/// whether to show the update screen.
bool isVersionOutdated(String? currentVersion, String? requiredVersion) {
  if (requiredVersion == null || requiredVersion.isEmpty) return false;
  if (currentVersion == null || currentVersion.isEmpty) return true;
  final current = _versionParts(currentVersion);
  final required = _versionParts(requiredVersion);
  final length = current.length > required.length
      ? current.length
      : required.length;
  for (var i = 0; i < length; i++) {
    final c = i < current.length ? current[i] : 0;
    final r = i < required.length ? required[i] : 0;
    if (c != r) return c < r;
  }
  return false;
}

List<int> _versionParts(String version) {
  final matches = RegExp(r'\d+').allMatches(version);
  return matches.map((m) => int.parse(m.group(0)!)).toList();
}
