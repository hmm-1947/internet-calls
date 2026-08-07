import 'package:flutter/material.dart';

class OnboardingPageData {
  final String title;
  final String body;
  final IconData icon;

  const OnboardingPageData({
    required this.title,
    required this.body,
    required this.icon,
  });
}

const List<OnboardingPageData> _defaultOnboardingPages = [
  OnboardingPageData(
    icon: Icons.headset_mic_outlined,
    title: 'Welcome',
    body:
        'Connect with real people through voice and video calls, and chat '
        'whenever you need someone to talk to.',
  ),
  OnboardingPageData(
    icon: Icons.shield_outlined,
    title: 'Please Read Before You Continue',
    body:
        'This app is a platform for casual conversation only. It is not a '
        'substitute for professional medical, mental health, or emergency '
        'services. If you are in crisis, please contact local emergency '
        'services or a qualified professional.',
  ),
  OnboardingPageData(
    icon: Icons.favorite_border,
    title: 'Be Respectful',
    body:
        'Calls and chats may be monitored for safety and quality. Abusive, '
        'illegal, or inappropriate behavior will result in account '
        'suspension. By continuing, you agree to our Terms & Conditions '
        'and Privacy Policy.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  final Widget Function(BuildContext context) nextScreenBuilder;
  final Color accentColor;
  final List<OnboardingPageData> pages;

  const OnboardingScreen({
    super.key,
    required this.nextScreenBuilder,
    this.accentColor = const Color(0xFF7C4DFF),
    this.pages = _defaultOnboardingPages,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLastPage => _index == widget.pages.length - 1;

  void _finish() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: widget.nextScreenBuilder));
  }

  void _next() {
    if (_isLastPage) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _isLastPage ? null : _finish,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: _isLastPage ? Colors.transparent : Colors.white54,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = widget.pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 96, color: widget.accentColor),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index ? widget.accentColor : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLastPage ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
