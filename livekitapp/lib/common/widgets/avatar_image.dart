import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class _FileExistsCache {
  static const _missTtlMs = 30000;
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

class AvatarImage extends StatefulWidget {
  final String? photoUrl;
  final double radius;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final double iconSize;
  final String? badgeLabel;
  final Color? badgeColor;

  const AvatarImage({
    super.key,
    required this.photoUrl,
    this.radius = 28,
    this.backgroundColor,
    this.fallbackIcon = Icons.person,
    this.iconSize = 28,
    this.badgeLabel,
    this.badgeColor,
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

  static String? badgeLabelOf(dynamic badgeTag) {
    if (badgeTag is Map) return badgeTag['name'] as String?;
    return null;
  }

  static Color? badgeColorOf(dynamic badgeTag) {
    if (badgeTag is Map) {
      final hex = badgeTag['color'] as String?;
      if (hex != null && hex.isNotEmpty) {
        final cleaned = hex.replaceFirst('#', '');
        final value = int.tryParse(
          cleaned.length == 6 ? 'FF$cleaned' : cleaned,
          radix: 16,
        );
        if (value != null) return Color(value);
      }
    }
    return null;
  }

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  String? _filePath;
  String? _remoteUrl;
  bool _fileFailed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) _resolve();
  }

  void _resolve() {
    _filePath = null;
    _remoteUrl = null;
    _fileFailed = false;
    final path = widget.photoUrl;
    if (path != null && path.isNotEmpty && !path.startsWith('http')) {
      final filePath = path.startsWith('file://')
          ? Uri.parse(path).toFilePath()
          : path;
      if (_FileExistsCache.exists(filePath)) {
        _filePath = filePath;
        return;
      }
      if (AvatarImage._isDeviceFilePath(path)) return;
    }
    final resolved = ApiConstants.resolveMediaUrl(widget.photoUrl);
    if (resolved.isEmpty) return;
    _remoteUrl = resolved;
    if (!AvatarCache.instance.isReady) {
      AvatarCache.instance.init().then((_) => _recoverFromDisk(resolved));
      return;
    }
    final cached = AvatarCache.instance.localPathSync(resolved);
    if (cached != null) {
      _filePath = cached;
      return;
    }
    AvatarCache.instance.ensureCached(resolved);
  }

  void _onFileError(String filePath) {
    _FileExistsCache.evict(filePath);
    final url = _remoteUrl;
    if (url != null) AvatarCache.instance.invalidate(url);
    if (!mounted || _fileFailed) return;
    setState(() {
      _fileFailed = true;
      _filePath = null;
    });
  }

  Future<void> _recoverFromDisk(String url) async {
    if (_fileFailed) return;
    final path = await AvatarCache.instance.ensureCached(url);
    if (path == null || !mounted || _remoteUrl != url) return;
    setState(() => _filePath = path);
  }

  Widget _fallback() => CircleAvatar(
    radius: widget.radius,
    backgroundColor: widget.backgroundColor ?? context.c.card2,
    child: Icon(
      widget.fallbackIcon,
      color: context.c.muted,
      size: widget.iconSize,
    ),
  );

  ImageProvider _sized(ImageProvider provider) {
    final pixels = (widget.radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 2048);
    return ResizeImage(provider, width: pixels, allowUpscaling: false);
  }

  Widget _badgeWrap(Widget child) {
    final label = widget.badgeLabel;
    if (label == null || label.isEmpty) return child;
    final color = widget.badgeColor ?? AppColors.brand;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          top: -(widget.radius * 0.32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.25)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.c.text, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.c.text,
                fontWeight: FontWeight.w800,
                fontSize: (widget.radius * 0.32).clamp(8, 11),
                height: 1.1,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filePath = _filePath;
    if (filePath != null) {
      return _badgeWrap(CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.backgroundColor ?? context.c.card2,
        backgroundImage: _sized(FileImage(File(filePath))),
        onBackgroundImageError: (_, _) => _onFileError(filePath),
      ));
    }
    final remoteUrl = _remoteUrl;
    if (remoteUrl == null) return _badgeWrap(_fallback());
    return _badgeWrap(CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor ?? context.c.card2,
      backgroundImage: _sized(NetworkImage(remoteUrl)),
      onBackgroundImageError: (_, _) => _recoverFromDisk(remoteUrl),
    ));
  }
}

/// Full-bleed rectangular hero image for edit-profile screens: a tall photo
/// with rounded bottom corners, matching the profile-view screens, as
/// opposed to [AvatarImage]'s small circular avatar.
class HeroProfileImage extends StatelessWidget {
  final String? photoUrl;
  final double height;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final BorderRadius borderRadius;

  const HeroProfileImage({
    super.key,
    required this.photoUrl,
    this.height = 320,
    this.backgroundColor,
    this.fallbackIcon = Icons.person,
    this.fallbackIconSize = 72,
    this.borderRadius = const BorderRadius.vertical(
      bottom: Radius.circular(28),
    ),
  });

  Widget _fallback() => Container(
    color: backgroundColor ?? const Color(0x339CA3AF),
    alignment: Alignment.center,
    child: Icon(fallbackIcon, color: AppColors.offline, size: fallbackIconSize),
  );

  Widget _image(ImageProvider provider) => Image(
    image: provider,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => _fallback(),
  );

  Widget _remote(String resolved) {
    if (resolved.isEmpty) return _fallback();
    final cached = AvatarCache.instance.localPathSync(resolved);
    if (cached != null) return _image(FileImage(File(cached)));
    AvatarCache.instance.ensureCached(resolved);
    return _image(NetworkImage(resolved));
  }

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
      } else if (AvatarImage._isDeviceFilePath(path)) {
        // A cached file the OS has since evicted. Falling through would
        // prefix the API base url onto a filesystem path and request a 404.
        child = _fallback();
      } else {
        child = _remote(ApiConstants.resolveMediaUrl(photoUrl));
      }
    } else {
      child = _remote(ApiConstants.resolveMediaUrl(photoUrl));
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: double.infinity, height: height, child: child),
    );
  }
}
