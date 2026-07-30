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

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty && !photoUrl!.startsWith('http')) {
      final file = File(photoUrl!);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: FileImage(file),
        );
      }
    }
    final resolved = ApiConstants.resolveMediaUrl(photoUrl);
    if (resolved.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: Icon(fallbackIcon, color: Colors.white54, size: iconSize),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: NetworkImage(resolved),
    );
  }
}