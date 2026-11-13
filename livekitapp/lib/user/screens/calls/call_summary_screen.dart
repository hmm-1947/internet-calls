import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

String _fmtDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: context.c.muted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? context.c.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class CallSummaryScreen extends StatefulWidget {
  final int callId;
  const CallSummaryScreen({super.key, required this.callId});

  @override
  State<CallSummaryScreen> createState() => _CallSummaryScreenState();
}

class _CallSummaryScreenState extends State<CallSummaryScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  Map<String, dynamic>? _summary;
  int _rating = 0;
  final _reviewController = TextEditingController();
  bool _submitting = false;
  bool _callingAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await _localStorage.getToken();
      final summary = await _repository.getCallSummary(token!, widget.callId);
      setState(() {
        _summary = summary;
        _rating = summary['existing_rating'] ?? 0;
        _reviewController.text = summary['existing_review'] ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submitRating() async {
    if (_rating == 0) return;
    setState(() => _submitting = true);
    try {
      final token = await _localStorage.getToken();
      await _repository.rateCall(
        token!,
        widget.callId,
        _rating,
        _reviewController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        PillMessage.showError(context, friendlyError(e));
      }
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _callAgain() async {
    if (_callingAgain || _summary == null) return;
    if (ActiveCallManager.instance.hasActiveCall) {
      PillMessage.show(context, 'You are already on a call');
      return;
    }
    setState(() => _callingAgain = true);
    try {
      final token = await _localStorage.getToken();
      final listenerId = _summary!['listener_id'] as int;
      final result = await _repository.initiateCall(
        token!,
        listenerId,
        callType: 'audio',
      );
      if (!mounted) return;
      ActiveCallManager.instance.start(
        ActiveCallInfo(
          role: ActiveCallRole.user,
          callId: result['call_id'],
          otherPartyName: _summary!['listener_name'] ?? 'Listener',
          otherPartyPhotoUrl: _summary!['listener_photo_url'],
          listenerId: listenerId,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        PillMessage.showError(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _callingAgain = false);
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pink = AppColors.brand;

    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.bg,
        elevation: 0,
        title: const Text(
          'Call Summary',
          style: TextStyle(color: pink, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: pink),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _summary == null
          ? Center(
              child: Text(
                'Failed to load summary',
                style: TextStyle(color: context.c.muted),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 120,
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: pink, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: pink.withOpacity(0.5),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: AvatarImage(
                      photoUrl: _summary!['listener_photo_url'],
                      radius: 56,
                      iconSize: 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Call with ${_summary!['listener_name']} Ended',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You shared a beautiful moment together',
                    style: TextStyle(color: context.c.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.access_time,
                          iconColor: context.c.textSecondary,
                          label: 'DURATION',
                          value: _fmtDuration(
                            _summary!['duration_seconds'] ?? 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.monetization_on,
                          iconColor: Colors.amber,
                          label: 'COINS SPENT',
                          value: '${_summary!['coins_deducted'] ?? 0} Coins',
                          valueColor: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _callingAgain ? null : _callAgain,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        side: BorderSide(color: context.c.muted),
                      ),
                      icon: _callingAgain
                          ? SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.c.text,
                              ),
                            )
                          : Icon(Icons.call, color: context.c.text),
                      label: Text(
                        'Call Again',
                        style: TextStyle(color: context.c.text),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.c.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'How was your call?',
                          style: TextStyle(
                            color: context.c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) {
                            final filled = i < _rating;
                            return IconButton(
                              onPressed: () => setState(() => _rating = i + 1),
                              icon: Icon(
                                filled ? Icons.star : Icons.star_border,
                                color: filled ? Colors.amber : context.c.faint,
                                size: 30,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reviewController,
                          maxLines: 3,
                          style: TextStyle(color: context.c.text),
                          decoration: InputDecoration(
                            hintText: 'Write a review (optional)',
                            hintStyle: TextStyle(color: context.c.faint),
                            filled: true,
                            fillColor: context.c.bg,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitRating,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _submitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.c.text,
                              ),
                            )
                          : Text(
                              'Submit Rating',
                              style: TextStyle(
                                color: context.c.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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
