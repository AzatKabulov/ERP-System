import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import 'platform_models.dart';

/// The words and colour for a client's state. A trial is shown as such while it is running.
(String, StatusTone) stateLook(AppLocalizations l, ClientRow row) =>
    switch (row.state) {
      'free' => (l.pfStateFree, StatusTone.info),
      'suspended' => (l.pfStateSuspended, StatusTone.danger),
      'read_only' => (l.pfStateReadOnly, StatusTone.danger),
      'grace' => (l.pfStateGrace, StatusTone.warning),
      'expiring' => (l.pfStateExpiring, StatusTone.warning),
      _ =>
        row.isTrial
            ? (l.pfStateTrial, StatusTone.info)
            : (l.pfStateActive, StatusTone.success),
    };

class StateBadge extends StatelessWidget {
  const StateBadge(this.row, {super.key});
  final ClientRow row;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = stateLook(strings(context), row);
    return StatusPill(label: label, tone: tone);
  }
}

/// "until 07.12.2026 · 30 days left" (or how long ago it ended, or "no end").
String endsText(AppLocalizations l, ClientRow row) {
  final end = row.endsAt;
  if (row.state == 'free' || end == null) return l.pfNoEnd;
  final days = row.daysLeft;
  final until = l.pfEndsOn(formatDay(end));
  if (days == null) return until;
  return '$until · ${days >= 0 ? l.pfDaysLeft(days) : l.pfDaysOver(-days)}';
}

String methodLabel(AppLocalizations l, String method) => switch (method) {
  'cash' => l.pfMethodCash,
  'card' => l.pfMethodCard,
  'transfer' => l.pfMethodTransfer,
  'other' => l.pfMethodOther,
  _ => l.pfNoMethod,
};

String eventLabel(AppLocalizations l, String kind) => switch (kind) {
  'created' => l.pfEventCreated,
  'trial' => l.pfEventTrial,
  'renew' => l.pfEventRenew,
  'extend' => l.pfEventExtend,
  'correction' => l.pfEventCorrection,
  'suspend' => l.pfEventSuspend,
  'resume' => l.pfEventResume,
  'free_on' => l.pfEventFreeOn,
  'free_off' => l.pfEventFreeOff,
  'password_reset' => l.pfEventPasswordReset,
  _ => kind,
};

String ticketLabel(AppLocalizations l, String status) => switch (status) {
  'answered' => l.pfTicketAnswered,
  'closed' => l.pfTicketClosed,
  _ => l.pfTicketOpen,
};

StatusTone ticketTone(String status) => switch (status) {
  'answered' => StatusTone.success,
  'closed' => StatusTone.neutral,
  _ => StatusTone.warning,
};

/// What went wrong with one field of a form, in words: the server's per-field answer, or "required".
String? fieldProblem(AppLocalizations l, ApiException? error, String field) {
  final problems = error?.fields[field];
  if (problems == null || problems.isEmpty) return null;
  final p = problems.first;
  return p.code == 'required' || p.code == 'blank'
      ? l.fieldRequired
      : p.message;
}

/// A short message for a failed request that is not about one field.
String generalProblem(AppLocalizations l, ApiException? error) =>
    error == null ? '' : apiErrorText(l, error);

/// One line of "label ... value" in a card.
class FactRow extends StatelessWidget {
  const FactRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

/// A title for a card's section.
Widget cardTitle(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: SectionHeading(text),
);

/// Copies [text] and says so.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showFeedback(context, strings(context).pfCopied);
}

/// A login or a password with a copy button: shown to the operator once, to hand to the owner.
class SecretLine extends StatelessWidget {
  const SecretLine({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
  });
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                SelectableText(
                  value,
                  key: valueKey,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.pfCopy,
            icon: AppIcon(AppIcons.copy, color: AppColors.blue),
            onPressed: () => copyToClipboard(context, value),
          ),
        ],
      ),
    );
  }
}
