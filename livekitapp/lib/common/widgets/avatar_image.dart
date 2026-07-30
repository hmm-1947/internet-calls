import 'dart:io';
import 'package:flutter/material.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

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

  @override
  Widget build(BuildContext context) {
    final path = photoUrl;
    if (path != null && path.isNotEmpty && !path.startsWith('http')) {
      final file = File(
        path.startsWith('file://') ? Uri.parse(path).toFilePath() : path,
      );
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: FileImage(file),
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
      backgroundImage: NetworkImage(resolved),
    );
  }
}