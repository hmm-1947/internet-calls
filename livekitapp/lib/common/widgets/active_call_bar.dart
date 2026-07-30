import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';

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

  @override
  Widget build(BuildContext context) {
    final manager = ActiveCallManager.instance;
    return ValueListenableBuilder<ActiveCallInfo?>(
      valueListenable: manager.current,
      builder: (context, info, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: manager.expanded,
          builder: (context, expanded, __) {
            final showBar = info != null && !expanded;
            return Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    if (showBar)
                      ActiveCallBar(info: info)
                    else
                      const SizedBox.shrink(),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: showBar,
                        child: child,
                      ),
                    ),
                  ],
                ),
                if (info != null)
                  Positioned.fill(
                    child: Offstage(
                      offstage: !expanded,
                      child: HeroControllerScope.none(
                        child: Navigator(
                          key: manager.callNavigatorKey,
                          onGenerateRoute: (settings) => PageRouteBuilder(
                            settings: settings,
                            pageBuilder: (routeContext, __, ___) =>
                                callScreenBuilder(routeContext, info),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
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
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
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
