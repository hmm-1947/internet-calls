import 'dart:io';
import 'package:flutter/material.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class _FileExistsCache {
  static const _missTtlMs = 5000;
  static const _maxEntries = 512;

  static final Set<String> _hits = <String>{};
  static final Map<String, int> _misses = <String, int>{};

  static bool exists(String path) {
    if (_hits.contains(path)) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final checkedAt = _misses[path];
    if (checkedAt != null && now - checkedAt < _missTtlMs) return false;

    bool found;
    try {
      found = File(path).existsSync();
    } catch (_) {
      found = false;
    }
    if (found) {
      _misses.remove(path);
      if (_hits.length >= _maxEntries) _hits.clear();
      _hits.add(path);
    } else {
      if (_misses.length >= _maxEntries) _misses.clear();
      _misses[path] = now;
    }
    return found;
  }

  static void evict(String path) {
    _hits.remove(path);
    _misses[path] = DateTime.now().millisecondsSinceEpoch;
  }
}

class AvatarImage extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final Color backgroundColor;
  final IconData fallbackIcon;
  final double iconSize;

  const AvatarImage({
    super.key,
    required this.photoUrl,
    this.radius = 28,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.fallbackIcon = Icons.person,
    this.iconSize = 28,
  });

  /// True for an on-device path (a cached avatar), as opposed to a path that is
  /// relative to the API host such as `/profile_photos/x.jpg`.
  static bool _isDeviceFilePath(String path) =>
      path.startsWith('file://') ||
      path.startsWith('/data/') ||
      path.startsWith('/storage/') ||
      path.startsWith('/var/') ||
      path.startsWith('/private/') ||
      path.contains('/cache/');

  Widget _fallback() => CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    child: Icon(fallbackIcon, color: Colors.white54, size: iconSize),
  );

  ImageProvider _sized(ImageProvider provider, BuildContext context) {
    final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 2048);
    return ResizeImage(provider, width: pixels, allowUpscaling: false);
  }

  @override
  Widget build(BuildContext context) {
    final path = photoUrl;
    if (path != null && path.isNotEmpty && !path.startsWith('http')) {
      final filePath = path.startsWith('file://')
          ? Uri.parse(path).toFilePath()
          : path;
      if (_FileExistsCache.exists(filePath)) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: _sized(FileImage(File(filePath)), context),
          onBackgroundImageError: (_, _) => _FileExistsCache.evict(filePath),
        );
      }
      // A cached file the OS has since evicted. Falling through would prefix
      // the API base url onto a filesystem path and request a 404.
      if (_isDeviceFilePath(path)) return _fallback();
    }
    final resolved = ApiConstants.resolveMediaUrl(photoUrl);
    if (resolved.isEmpty) {
      return _fallback();
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: _sized(NetworkImage(resolved), context),
      onBackgroundImageError: (_, _) {},
    );
  }
}

/// Full-bleed rectangular hero image for edit-profile screens: a tall photo
/// with rounded bottom corners, matching the profile-view screens, as
/// opposed to [AvatarImage]'s small circular avatar.
class HeroProfileImage extends StatelessWidget {
  final String? photoUrl;
  final double height;
  final Color backgroundColor;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final BorderRadius borderRadius;

  const HeroProfileImage({
    super.key,
    required this.photoUrl,
    this.height = 320,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.fallbackIcon = Icons.person,
    this.fallbackIconSize = 72,
    this.borderRadius = const BorderRadius.vertical(
      bottom: Radius.circular(28),
    ),
  });

  Widget _fallback() => Container(
    color: backgroundColor,
    alignment: Alignment.center,
    child: Icon(fallbackIcon, color: Colors.white54, size: fallbackIconSize),
  );

  Widget _image(ImageProvider provider) => Image(
    image: provider,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => _fallback(),
  );

  @override
  Widget build(BuildContext context) {
    Widget child;
    final path = photoUrl;
    if (path != null && path.isNotEmpty && !path.startsWith('http')) {
      final filePath = path.startsWith('file://')
          ? Uri.parse(path).toFilePath()
          : path;
      if (_FileExistsCache.exists(filePath)) {
        child = _image(FileImage(File(filePath)));
      } else {
        child = _fallback();
      }
    } else {
      final resolved = ApiConstants.resolveMediaUrl(photoUrl);
      child = resolved.isEmpty ? _fallback() : _image(NetworkImage(resolved));
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: double.infinity, height: height, child: child),
    );
  }
}
