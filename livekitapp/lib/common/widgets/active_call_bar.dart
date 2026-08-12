import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';
import 'package:livekitapp/common/widgets/call_ui.dart';
import 'package:livekitapp/common/widgets/minimized_call_video.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_message_bar.dart';
import 'package:livekitapp/user/services/pip_service.dart';

typedef ActiveCallScreenBuilder =
    Widget Function(BuildContext context, ActiveCallInfo info);

String formatCallDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class ActiveCallHost extends StatelessWidget {
  final Widget child;
  final ActiveCallScreenBuilder callScreenBuilder;

  const ActiveCallHost({
    super.key,
    required this.child,
    required this.callScreenBuilder,
  });

  /// Height reserved for the stacked bars, so the floating video window opens
  /// below them rather than behind them.
  static const _callBarHeight = 56.0;
  static const _voiceBarHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final manager = ActiveCallManager.instance;
    final player = VoiceMessagePlayer.instance;
    // One builder over every source that can show or hide a bar, instead of a
    // stack of nested ValueListenableBuilders.
    return ListenableBuilder(
      listenable: Listenable.merge([
        manager.current,
        manager.expanded,
        player.activeTrack,
        player.visibleChatKey,
        PipService.instance.isInPip,
      ]),
      builder: (context, _) {
        final info = manager.current.value;
        // In picture-in-picture the window is a thumbnail: the call video has
        // to take it over, and the screen underneath plus the bars must stop
        // laying out there, since neither fits.
        final pip =
            info != null &&
            (PipService.instance.isInPip.value ||
                isCompactCallWindow(MediaQuery.sizeOf(context)));
        // Forced open while in PiP, so a minimized call still renders its video
        // into the thumbnail instead of leaving it blank.
        final expanded = manager.expanded.value || pip;
        final voiceTrack = player.activeTrack.value;
        final showCallBar = info != null && !expanded;
        // A note playing in the chat that is on screen already has its bubble,
        // so the bar is only for playback the user has navigated away from.
        final showVoiceBar = !pip && voiceTrack != null && player.shouldShowBar;
        final bars = <Widget>[
          if (showCallBar) ActiveCallBar(info: info),
          if (showVoiceBar)
            VoiceMessageBar(track: voiceTrack, applyTopPadding: !showCallBar),
        ];
        final barsHeight =
            (showCallBar ? _callBarHeight : 0) +
            (showVoiceBar ? _voiceBarHeight : 0) +
            MediaQuery.paddingOf(context).top;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Offstage rather than dropped from the tree: it skips layout and
            // paint (so nothing overflows in a thumbnail window) while keeping
            // the state of whatever screen the user was on.
            Offstage(
              offstage: pip,
              child: Column(
                children: [
                  ...bars,
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: bars.isNotEmpty,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
            if (info != null)
              Positioned.fill(
                child: Offstage(
                  offstage: !expanded,
                  // Slid away rather than dropped, so leaving the call (the
                  // "No answer" screen closing itself, or the user cancelling
                  // it) reveals the screen underneath with the same motion as
                  // a page pop. The navigator is passed as `child` so the call
                  // screen keeps its state across the animation.
                  child: ValueListenableBuilder<bool>(
                    valueListenable: manager.dismissing,
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: manager.callNavigatorKey,
                        onGenerateRoute: (settings) => PageRouteBuilder(
                          settings: settings,
                          // Built off `current` rather than the captured
                          // `info`: this route is generated once and kept, so a
                          // call swapped in place (the redial after a decline)
                          // would otherwise keep rendering the call it
                          // replaced. The screen is keyed on the call id, so a
                          // new id rebuilds it from scratch.
                          pageBuilder: (routeContext, _, _) =>
                              ValueListenableBuilder<ActiveCallInfo?>(
                                valueListenable: manager.current,
                                builder: (builderContext, currentInfo, _) =>
                                    currentInfo == null
                                    ? const SizedBox.shrink()
                                    : callScreenBuilder(
                                        builderContext,
                                        currentInfo,
                                      ),
                              ),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      ),
                    ),
                    builder: (context, dismissing, child) => AnimatedSlide(
                      offset: dismissing ? const Offset(0, 1) : Offset.zero,
                      duration: ActiveCallManager.dismissAnimationDuration,
                      curve: Curves.easeInCubic,
                      child: child,
                    ),
                  ),
                ),
              ),
            if (showCallBar && info.isVideo)
              Positioned.fill(child: MinimizedCallVideo(topInset: barsHeight)),
          ],
        );
      },
    );
  }
}

class ActiveCallBar extends StatelessWidget {
  final ActiveCallInfo info;

  const ActiveCallBar({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final manager = ActiveCallManager.instance;
    return Material(
      color: const Color(0xFF17202E),
      child: InkWell(
        onTap: manager.expand,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  onPressed: manager.expand,
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                ),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: manager.statusText,
                    builder: (context, status, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: manager.durationSeconds,
                        builder: (context, seconds, __) {
                          final label = status.isNotEmpty
                              ? status
                              : formatCallDuration(seconds);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                info.otherPartyName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: manager.hangUp,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53950),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
