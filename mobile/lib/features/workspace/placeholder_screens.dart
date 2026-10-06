import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../widgets/common.dart';
import '../admin/administration_screen.dart';

/// Shown for pages whose workflow is not connected to the server yet. It says so
/// plainly: a real build never shows demonstration data as if it were real.
class UnavailableScreen extends StatelessWidget {
  const UnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SurfaceCard(
          child: EmptyState(
            title: l.unavailableTitle,
            subtitle: l.unavailableBody,
            icon: Icons.schedule_outlined,
          ),
        ),
      ],
    );
  }
}

/// The real dashboard is a later phase; for now it greets the user and shows the
/// business and role they are working in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final user = session.user;
    final membership = session.membership;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l.welcomeUser(user?.displayName ?? ''),
          key: const ValueKey('welcome'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (membership != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.businessName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(roleLabel(l, membership.role)),
                if (session.location != null) Text(session.location!.name),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const UnavailableScreenCard(),
      ],
    );
  }
}

class UnavailableScreenCard extends StatelessWidget {
  const UnavailableScreenCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: EmptyState(
        title: l.unavailableTitle,
        subtitle: l.unavailableBody,
        icon: Icons.schedule_outlined,
      ),
    );
  }
}

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
