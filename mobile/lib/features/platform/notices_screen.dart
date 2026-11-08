import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../shared/async_section.dart';
import '../shared/loading_skeletons.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';

/// Short messages every shop sees at the top of the app ("maintenance tonight").
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key, required this.repository});
  final PlatformRepository repository;

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final _list = GlobalKey<AsyncSectionState<List<NoticeRow>>>();

  Future<void> _new() async {
    final made = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewNoticeDialog(repository: widget.repository),
    );
    if (made == true) _list.currentState?.reload();
  }

  Future<void> _toggle(NoticeRow n, bool on) async {
    try {
      await widget.repository.setNoticeActive(n.id, on);
    } on ApiException catch (_) {
      // the list below is read again and shows what the server holds
    }
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768;
    return SingleChildScrollView(
      padding: pagePadding(context, compact: narrow),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(
                title: l.pfNotices,
                subtitle: l.pfNoticesIntro,
                actions: [
                  PrimaryButton(
                    key: const ValueKey('pf-new-notice'),
                    label: l.pfNewNotice,
                    icon: AppIcons.plus,
                    onPressed: _new,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AsyncSection<List<NoticeRow>>(
                loadingBuilder: (context) =>
                    const RecordListSkeleton(rows: 3, rowHeight: 132),
                key: _list,
                load: widget.repository.notices,
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return SurfaceCard(
                      child: EmptyState(
                        key: const ValueKey('pf-no-notices'),
                        title: l.pfNoNotices,
                        icon: AppIcons.mail,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final n in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SurfaceCard(
                            key: ValueKey('notice-${n.id}'),
                            flat: true,
                            padding: 16,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.messageRu,
                                        style: const TextStyle(height: 1.4),
                                      ),
                                      if (n.messageTk.isNotEmpty)
                                        Text(
                                          n.messageTk,
                                          style: TextStyle(
                                            color: AppColors.neutral,
                                            height: 1.4,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatDay(n.startsAt)} – ${formatDay(n.endsAt)}',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  key: ValueKey('notice-switch-${n.id}'),
                                  value: n.isActive,
                                  onChanged: (v) => _toggle(n, v),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewNoticeDialog extends StatefulWidget {
  const _NewNoticeDialog({required this.repository});
  final PlatformRepository repository;

  @override
  State<_NewNoticeDialog> createState() => _NewNoticeDialogState();
}

class _NewNoticeDialogState extends State<_NewNoticeDialog> {
  final _ru = TextEditingController();
  final _tk = TextEditingController();
  late DateTime _from = DateTime.now();
  late DateTime _until = DateTime.now().add(const Duration(days: 3));
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _ru.dispose();
    _tk.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_ru.text.trim().isEmpty) {
      setState(
        () => _error = const ApiException(
          kind: ApiErrorKind.client,
          code: 'validation_error',
          fields: {
            'message_ru': [FieldError('required', '')],
          },
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createNotice(
        messageRu: _ru.text.trim(),
        messageTk: _tk.text.trim(),
        startsAt: DateTime(_from.year, _from.month, _from.day),
        // the whole last day
        endsAt: DateTime(_until.year, _until.month, _until.day, 23, 59),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AppDialog(
      title: l.pfNewNotice,
      icon: AppIcons.mail,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: l.pfMessageRu,
            child: TextField(
              key: const ValueKey('pf-notice-ru'),
              controller: _ru,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                errorText: fieldProblem(l, _error, 'message_ru'),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: l.pfMessageTk,
            child: TextField(
              key: const ValueKey('pf-notice-tk'),
              controller: _tk,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: l.pfShownFrom,
                  child: OutlinedButton(
                    key: const ValueKey('pf-notice-from'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final d = await _pick(_from);
                            if (d != null) setState(() => _from = d);
                          },
                    child: Text(formatDay(_from)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LabeledField(
                  label: l.pfShownUntil,
                  child: OutlinedButton(
                    key: const ValueKey('pf-notice-until'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final d = await _pick(_until);
                            if (d != null) setState(() => _until = d);
                          },
                    child: Text(formatDay(_until)),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null && _error!.fields.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                generalProblem(l, _error),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          if (fieldProblem(l, _error, 'ends_at') case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(problem, style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pf-notice-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
