import 'package:flutter/material.dart';
import 'package:listener/screens/calls/recordings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/call_log_store.dart';

class LogsScreen extends StatefulWidget {
  final void Function(String username)? onCallUser;

  const LogsScreen({super.key, this.onCallUser});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String? _role;
  String? _username;
  @override
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _role = p.getString('role');
          _username = p.getString('username');
        });
        CallLogStore.instance.load(_username ?? '').then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    }

    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    }

    if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }

    if (diff.inDays == 1) {
      return 'Yesterday';
    }

    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final logs = CallLogStore.instance.logs;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: const Text(
          'Calls',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search, color: Colors.white70),
          ),
          if (_role == 'listener' && _username != null)
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.white70),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecordingsScreen(username: _username!),
                ),
              ),
            ),
          PopupMenuButton<String>(
            color: const Color(0xFF1A1A1A),
            onSelected: (value) async {
              if (value == "clear") {
                await CallLogStore.instance.clear(_username ?? '');

                if (mounted) {
                  setState(() {});
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: "clear",
                child: Text(
                  "Clear History",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert, color: Colors.white70),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, color: Color(0xFF2A2A2A), size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No call history yet',
                    style: TextStyle(color: Color(0xFF555555), fontSize: 15),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];

                final statusColor = log.missed
                    ? const Color(0xFFFF4D4F)
                    : const Color(0xFF22C55E);

                final statusIcon = log.missed
                    ? Icons.call_missed
                    : log.outgoing
                    ? Icons.call_made
                    : Icons.call_received;

                final statusText = log.missed
                    ? 'Missed Call'
                    : '${(log.durationSeconds / 60).toStringAsFixed(2)} min';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      widget.onCallUser?.call(log.name);
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              log.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    statusIcon,
                                    color: statusColor,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatTime(log.time),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
