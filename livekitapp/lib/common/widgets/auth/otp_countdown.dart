import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';

/// Shows a live countdown for OTP validity. When it hits zero, calls
/// [onExpire] and swaps itself for a "Resend OTP" control which calls
/// [onResend] and restarts the countdown.
class OtpCountdown extends StatefulWidget {
  final int seconds;
  final VoidCallback onExpire;
  final Future<void> Function() onResend;

  const OtpCountdown({
    super.key,
    this.seconds = 60,
    required this.onExpire,
    required this.onResend,
  });

  @override
  State<OtpCountdown> createState() => OtpCountdownState();
}

class OtpCountdownState extends State<OtpCountdown> {
  late int _remaining;
  Timer? _timer;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
        widget.onExpire();
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  /// Restarts the countdown, e.g. after a fresh OTP has been sent.
  void restart() {
    if (!mounted) return;
    setState(() => _remaining = widget.seconds);
    _startTimer();
  }

  Future<void> _handleResend() async {
    setState(() => _resending = true);
    try {
      await widget.onResend();
      restart();
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: context.c.overlay,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: context.c.muted, size: 16),
            const SizedBox(width: 6),
            Text(
              'OTP expires in $_formatted',
              style: TextStyle(color: context.c.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
              SizedBox(width: 6),
              Text(
                'OTP expired',
                style: TextStyle(
                  color: AppColors.brand,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _resending ? null : _handleResend,
          icon: _resending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand,
                  ),
                )
              : const Icon(Icons.refresh, color: AppColors.brand, size: 18),
          label: Text(
            _resending ? 'Sending…' : 'Resend OTP',
            style: const TextStyle(
              color: AppColors.brand,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
