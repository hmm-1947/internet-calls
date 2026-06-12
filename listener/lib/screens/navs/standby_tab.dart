import 'package:flutter/material.dart';

class StandbyTab extends StatelessWidget {
  final String? username;
  const StandbyTab({super.key, this.username});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.headset, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Hello, ${username ?? ''}',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Waiting for calls...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
