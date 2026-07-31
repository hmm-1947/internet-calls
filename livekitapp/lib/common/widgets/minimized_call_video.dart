import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';

/// Floating picture-in-picture window for a minimized video call.
///
/// The call screen stays alive (offstage) while minimized, so its video tracks
/// are still receiving frames; this renders the same track in a small draggable
/// window over whatever screen the user moved on to. Tapping it reopens the
/// call.
class MinimizedCallVideo extends StatefulWidget {
  /// Space already taken by the bars above, so the window never starts under
  /// them.
  final double topInset;

  const MinimizedCallVideo({super.key, this.topInset = 0});

  @override
  State<MinimizedCallVideo> createState() => _MinimizedCallVideoState();
}

class _MinimizedCallVideoState extends State<MinimizedCallVideo> {
  static const _width = 104.0;
  static const _height = 156.0;
  static const _margin = 12.0;

  /// Null until first laid out or dragged, so the window sits in its default
  /// corner without needing the viewport size up front.
  Offset? _offset;

  Offset _clamp(Offset offset, Size bounds) {
    final maxX = (bounds.width - _width - _margin).clamp(
      _margin,
      double.infinity,
    );
    final maxY = (bounds.height - _height - _margin).clamp(
      _margin,
      double.infinity,
    );
    return Offset(
      offset.dx.clamp(_margin, maxX),
      offset.dy.clamp(widget.topInset + _margin, maxY),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoTrack?>(
      valueListenable: ActiveCallManager.instance.minimizedVideoTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final bounds = Size(constraints.maxWidth, constraints.maxHeight);
            final position = _clamp(
              _offset ??
                  Offset(
                    bounds.width - _width - _margin,
                    widget.topInset + _margin,
                  ),
              bounds,
            );
            return Stack(
              children: [
                Positioned(
                  left: position.dx,
                  top: position.dy,
                  width: _width,
                  height: _height,
                  child: GestureDetector(
                    onTap: ActiveCallManager.instance.expand,
                    onPanUpdate: (details) => setState(
                      () => _offset = _clamp(position + details.delta, bounds),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoTrackRenderer(track, fit: VideoViewFit.cover),
                          const Positioned(
                            right: 2,
                            top: 2,
                            child: Icon(
                              Icons.fullscreen,
                              size: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
