import 'package:flutter/material.dart';

class CallLogsTab extends StatelessWidget {
  const CallLogsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No call logs yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
