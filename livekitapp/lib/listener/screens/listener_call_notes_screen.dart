import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';

class ListenerCallNotesScreen extends StatefulWidget {
  final int? callId;
  final int? userId;
  final String otherPartyName;

  const ListenerCallNotesScreen({
    super.key,
    this.callId,
    this.userId,
    this.otherPartyName = 'User',
  });

  @override
  State<ListenerCallNotesScreen> createState() =>
      _ListenerCallNotesScreenState();
}

class _ListenerCallNotesScreenState extends State<ListenerCallNotesScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _savedText = '';
  String? _userName;
  DateTime? _lastCallAt;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    if (widget.callId == null && widget.userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final token = await _localStorage.getToken();
      final note = widget.callId != null
          ? await _repository.getNoteByCall(token!, widget.callId!)
          : await _repository.getNoteByUser(token!, widget.userId!);
      if (note != null) {
        _controller.text = note['note'] ?? '';
        _userName = note['user_name'];
        final lastCall = note['last_call_at'];
        if (lastCall != null) _lastCallAt = DateTime.tryParse(lastCall);
      }
    } catch (_) {}
    _savedText = _controller.text;
    if (mounted) setState(() => _loading = false);
  }

  bool get _hasUnsavedChanges => _controller.text != _savedText;

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2430),
        title: const Text(
          'Unsaved changes',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You have unsaved notes. Do you want to save before leaving?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text(
              'Close without saving',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFFE53950)),
            ),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _save();
      return true;
    }
    return result == 'discard';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await _localStorage.getToken();
      await _repository.saveNote(
        token!,
        callId: widget.callId,
        userId: widget.userId,
        note: _controller.text.trim(),
      );
      _savedText = _controller.text;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Note saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year} • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0F1A),
          title: Text('Notes about ${widget.otherPartyName}'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFFE53950),
                          child: Text(
                            (_userName ?? widget.otherPartyName).isNotEmpty
                                ? (_userName ?? widget.otherPartyName)[0]
                                      .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName ?? widget.otherPartyName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _lastCallAt != null
                                    ? 'Last called: ${_formatDate(_lastCallAt!)}'
                                    : 'No previous calls',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Write your thoughts about this user...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF1F2430),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53950),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
