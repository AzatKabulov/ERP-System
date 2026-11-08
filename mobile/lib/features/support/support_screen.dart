import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import '../shared/loading_skeletons.dart';
import 'support_repository.dart';

/// Writing to us and reading our answers. Only an owner or a manager may write (a seller tells
/// them instead); everyone can see how to reach us.
class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    required this.session,
    required this.repository,
    this.screenName = '',
  });

  final SessionController session;
  final SupportRepository repository;

  /// Where in the app the person was, sent along so we can see what they saw.
  final String screenName;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _section = GlobalKey<AsyncSectionState<List<SupportRequest>>>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  bool _writing = false;
  ApiException? _error;
  bool _sent = false;

  bool get _canWrite => widget.session.can('support.write');

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(
        () => _error = const ApiException(
          kind: ApiErrorKind.client,
          code: 'validation_error',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        screen: widget.screenName,
      );
      if (!mounted) return;
      _subject.clear();
      _body.clear();
      setState(() {
        _writing = false;
        _sent = true;
      });
      _section.currentState?.reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _contact(AppLocalizations l) {
    final platform = widget.session.platform;
    if (!platform.hasContact) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (platform.supportPhone.isNotEmpty)
              Text(
                l.supportPhoneLine(platform.supportPhone),
                key: const ValueKey('support-phone'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (platform.supportNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                platform.supportNote,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.supportIntro,
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: l.supportSubject,
          child: TextField(
            key: const ValueKey('support-subject'),
            controller: _subject,
            enabled: !_busy,
            maxLength: 160,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              counterText: '',
              errorText: _error != null && _subject.text.trim().isEmpty
                  ? l.fieldRequired
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: l.supportMessage,
          child: TextField(
            key: const ValueKey('support-body'),
            controller: _body,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(
              counterText: '',
              errorText: _error != null && _body.text.trim().isEmpty
                  ? l.fieldRequired
                  : null,
            ),
          ),
        ),
        if (_error != null &&
            _subject.text.trim().isNotEmpty &&
            _body.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            apiErrorText(l, _error!),
            key: const ValueKey('support-error'),
            style: TextStyle(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                key: const ValueKey('support-send'),
                label: l.supportSend,
                icon: AppIcons.send,
                onPressed: _busy ? null : _send,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _writing = false),
              child: Text(l.cancel),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.supportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _contact(l),
                  if (!_canWrite)
                    NoticeBanner(
                      key: const ValueKey('support-owners-only'),
                      text: l.supportOwnersOnly,
                    )
                  else ...[
                    if (_sent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: NoticeBanner(
                          key: const ValueKey('support-sent'),
                          text: l.supportSentOk,
                          tone: StatusTone.success,
                          icon: AppIcons.checkCircle,
                        ),
                      ),
                    if (_writing)
                      _form(l)
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PrimaryButton(
                          key: const ValueKey('support-new'),
                          label: l.supportNewRequest,
                          icon: AppIcons.chat,
                          onPressed: () => setState(() {
                            _writing = true;
                            _sent = false;
                            _error = null;
                          }),
                        ),
                      ),
                    const SizedBox(height: 20),
                    AsyncSection<List<SupportRequest>>(
                      loadingBuilder: (context) =>
                          const RecordListSkeleton(rows: 3, rowHeight: 132),
                      key: _section,
                      load: widget.repository.list,
                      builder: (context, requests) {
                        if (requests.isEmpty) {
                          return SurfaceCard(
                            child: EmptyState(
                              key: const ValueKey('support-empty'),
                              title: l.supportEmpty,
                              subtitle: l.supportEmptyHint,
                              icon: AppIcons.chat,
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final r in requests)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _RequestCard(
                                  key: ValueKey('support-${r.id}'),
                                  request: r,
                                  repository: widget.repository,
                                  onChanged: () =>
                                      _section.currentState?.reload(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.repository,
    required this.onChanged,
  });

  final SupportRequest request;
  final SupportRepository repository;
  final VoidCallback onChanged;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  final _reply = TextEditingController();
  bool _open = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.reply(widget.request.id, text);
      if (!mounted) return;
      _reply.clear();
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final r = widget.request;
    final (label, tone) = switch (r.status) {
      'answered' => (l.supportStatusAnswered, AppColors.success),
      'closed' => (l.supportStatusClosed, AppColors.muted),
      _ => (l.supportStatusOpen, AppColors.warning),
    };
    // A request that has our answer is opened by default: that is why the person came back.
    final expanded = _open || r.status == 'answered';
    return SurfaceCard(
      flat: true,
      onTap: expanded && _open ? null : () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.subject,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatStamp(r.updatedAt),
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            for (final m in r.messages)
              Align(
                alignment: m.fromStore
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: m.fromStore ? AppColors.tint : AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${m.fromStore ? l.supportFromYou : l.supportFromUs} · ${formatStamp(m.createdAt)}',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(m.text, style: const TextStyle(height: 1.4)),
                    ],
                  ),
                ),
              ),
            if (r.isClosed)
              Text(
                l.supportClosedNote,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              )
            else ...[
              const SizedBox(height: 4),
              TextField(
                key: ValueKey('support-reply-${r.id}'),
                controller: _reply,
                enabled: !_busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: l.supportReplyHint,
                  suffixIcon: IconButton(
                    key: ValueKey('support-reply-send-${r.id}'),
                    tooltip: l.supportSend,
                    icon: AppIcon(AppIcons.send, color: AppColors.blue),
                    onPressed: _busy ? null : _send,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    apiErrorText(l, _error!),
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
