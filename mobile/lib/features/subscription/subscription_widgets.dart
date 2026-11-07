import 'package:flutter/material.dart';

import '../../core/format/format_stamp.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';

bool _manages(SessionController session) =>
    session.membership?.role == 'owner' ||
    session.membership?.role == 'manager';

/// How to reach us, for a shop whose subscription needs attention.
Future<void> showRenewDialog(
  BuildContext context,
  SessionController session, {
  VoidCallback? onWriteToUs,
}) {
  final l = strings(context);
  final platform = session.platform;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('renew-dialog'),
      title: Text(l.subRenewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.subRenewBody, style: const TextStyle(height: 1.5)),
          if (platform.supportPhone.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l.subCall(platform.supportPhone),
              key: const ValueKey('renew-phone'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (platform.supportNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              platform.supportNote,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
        if (onWriteToUs != null)
          FilledButton(
            key: const ValueKey('renew-write-us'),
            onPressed: () {
              Navigator.of(context).pop();
              onWriteToUs();
            },
            child: Text(l.subWriteUs),
          ),
      ],
    ),
  );
}

/// The warning above every page when the subscription is ending or has ended. The owner and
/// managers get the dates and a way to renew; a seller only learns that work is blocked.
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({
    super.key,
    required this.session,
    required this.onRenew,
  });

  final SessionController session;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final sub = session.subscription;
    if (sub == null) return const SizedBox.shrink();
    final l = strings(context);
    final manages = _manages(session);
    final String text;
    final StatusTone tone;
    switch (sub.state) {
      case 'expiring':
        final days = sub.daysLeft ?? 0;
        final date = sub.endsAt == null ? '' : formatDay(sub.endsAt!);
        text = days <= 0
            ? l.subBannerExpiringToday
            : sub.isTrial
            ? l.subBannerTrial(date, '$days')
            : l.subBannerExpiring(date, '$days');
        tone = StatusTone.warning;
      case 'grace':
        final until = sub.graceEndsAt == null
            ? ''
            : formatDay(sub.graceEndsAt!);
        text = l.subBannerGrace(until);
        tone = StatusTone.danger;
      case 'read_only':
        text = manages ? l.subBannerReadOnly : l.subBannerReadOnlyStaff;
        tone = StatusTone.danger;
      case 'active' when sub.isTrial && manages:
        final days = sub.daysLeft ?? 0;
        final date = sub.endsAt == null ? '' : formatDay(sub.endsAt!);
        text = l.subBannerTrial(date, '$days');
        tone = StatusTone.info;
      default:
        return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('subscription-banner'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: NoticeBanner(
        text: text,
        tone: tone,
        icon: tone == StatusTone.info ? AppIcons.info : AppIcons.warning,
        action: manages && sub.state != 'active'
            ? Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('subscription-renew'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 40),
                  ),
                  onPressed: onRenew,
                  child: Text(l.subRenewAction),
                ),
              )
            : null,
      ),
    );
  }
}

/// A notice from us to every shop, which the person can close.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final items = session.announcements;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final AnnouncementInfo a in items)
          Padding(
            key: ValueKey('announcement-${a.id}'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: NoticeBanner(
              text: a.message,
              action: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('announcement-hide-${a.id}'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 40),
                  ),
                  onPressed: () => session.dismissAnnouncement(a.id),
                  child: Text(l.hideNotice),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What a suspended shop sees instead of its pages: we cut access, here is how to reach us.
class SubscriptionBlockedScreen extends StatelessWidget {
  const SubscriptionBlockedScreen({
    super.key,
    required this.session,
    this.onWriteToUs,
  });

  final SessionController session;
  final VoidCallback? onWriteToUs;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final platform = session.platform;
    final manages = _manages(session);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.warningTint,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.block,
                          size: 26,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.subSuspendedTitle,
                    key: const ValueKey('suspended-title'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    manages ? l.subSuspendedBody : l.subSuspendedStaff,
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  if (platform.supportPhone.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      l.subCall(platform.supportPhone),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (platform.supportNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      platform.supportNote,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (onWriteToUs != null && manages)
                    PrimaryButton(
                      key: const ValueKey('suspended-write-us'),
                      label: l.subWriteUs,
                      icon: AppIcons.chat,
                      onPressed: onWriteToUs,
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('suspended-sign-out'),
                    onPressed: session.signOut,
                    child: Text(l.signOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
