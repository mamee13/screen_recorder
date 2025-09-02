import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  static const String email = 'support@example.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need help?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Reach out and we'll get back to you."),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.mail_rounded),
                title: const Text('Email'),
                subtitle: const Text(email),
                trailing: TextButton(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: email));
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email copied')));
                  },
                  child: const Text('Copy'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Version'),
                subtitle: Text('1.0.0'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
