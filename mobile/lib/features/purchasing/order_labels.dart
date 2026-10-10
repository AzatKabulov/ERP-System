import '../../l10n/app_localizations.dart';

String orderStatusLabel(AppLocalizations l, String status) => switch (status) {
  'draft' => l.statusDraft,
  'ordered' => l.statusOrdered,
  'partially_received' => l.statusPartial,
  'received' => l.statusReceived,
  'cancelled' => l.statusCancelled,
  _ => status,
};
