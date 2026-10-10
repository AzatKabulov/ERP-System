import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../widgets/common.dart';

/// A user who belongs to no active business.
class NoBusinessScreen extends StatelessWidget {
  const NoBusinessScreen({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.noBusiness,
                  key: const ValueKey('no-business'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('no-business-sign-out'),
                  onPressed: session.signOut,
                  icon: const Icon(Icons.logout),
                  label: Text(l.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
