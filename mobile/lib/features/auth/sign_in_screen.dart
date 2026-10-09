import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/config/server_settings.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'password_reset_screen.dart';

/// The first screen of a real (non-demo) build. A language switch is offered here
/// because it applies before anyone has signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.session,
    required this.languageCode,
    required this.onLanguageChanged,
    required this.server,
  });

  final SessionController session;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  /// Where this device signs in: the address is chosen here and kept on the device.
  final ServerSettings server;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  void _serverChanged() => setState(() => _error = null);

  @override
  void initState() {
    super.initState();
    widget.server.addListener(_serverChanged);
  }

  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    widget.server.removeListener(_serverChanged);
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // never two sign-in requests at once
    final username = _username.text.trim();
    if (username.isEmpty || _password.text.isEmpty) {
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
      await widget.session.signIn(username, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final session = widget.session;
    return Scaffold(
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
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String>(
                      key: const ValueKey('language-selector'),
                      tooltip: l.language,
                      initialValue: widget.languageCode,
                      onSelected: widget.onLanguageChanged,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'ru',
                          child: Text(l.languageRussian),
                        ),
                        PopupMenuItem(
                          value: 'tk',
                          child: Text(l.languageTurkmen),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.translate,
                              size: 20,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.languageCode == 'ru'
                                  ? l.languageRussian
                                  : l.languageTurkmen,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SurfaceCard(
                    padding: 28,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l.appName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.signInTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.signInSubtitle,
                            style: const TextStyle(
                              color: AppColors.muted,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (session.sessionExpired)
                            _Notice(
                              text: l.sessionExpiredNotice,
                              key: const ValueKey('notice-expired'),
                            ),
                          if (session.serverUnreachable)
                            _Notice(
                              text: l.serverUnreachableNotice,
                              key: const ValueKey('notice-unreachable'),
                              action: TextButton(
                                key: const ValueKey('retry-restore'),
                                onPressed: session.restore,
                                child: Text(l.retry),
                              ),
                            ),
                          if (!widget.server.configured)
                            _Notice(
                              text: l.serverNotConfigured,
                              key: const ValueKey('notice-unconfigured'),
                            ),
                          TextField(
                            key: const ValueKey('sign-in-username'),
                            controller: _username,
                            enabled: !_busy,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: l.username,
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('sign-in-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: l.password,
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                key: const ValueKey('sign-in-error'),
                                apiErrorText(l, _error!),
                                style: const TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          GradientButton(
                            key: const ValueKey('sign-in-submit'),
                            label: _busy ? l.signingIn : l.signInAction,
                            icon: Icons.login,
                            onPressed: _busy || !widget.server.configured
                                ? null
                                : _submit,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            key: const ValueKey('forgot-password'),
                            onPressed: _busy || !widget.server.configured
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PasswordResetScreen(
                                        api: widget.session.api,
                                        initialIdentifier: _username.text
                                            .trim(),
                                      ),
                                    ),
                                  ),
                            child: Text(l.forgotPassword),
                          ),
                          if (!widget.server.fixed) ...[
                            const Divider(height: 24),
                            _ServerLine(server: widget.server, enabled: !_busy),
                          ],
                        ],
                      ),
                    ),
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

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(height: 1.4)),
        ?action,
      ],
    ),
  );
}

/// "Server: https://..." with a way to change it. Shown on every sign-in: an installation is
/// not tied to one shop's server.
class _ServerLine extends StatelessWidget {
  const _ServerLine({required this.server, required this.enabled});

  final ServerSettings server;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          server.configured ? l.serverLine(server.url) : l.serverNone,
          key: const ValueKey('server-line'),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        TextButton(
          key: const ValueKey('server-change'),
          onPressed: enabled
              ? () => showDialog<void>(
                  context: context,
                  builder: (_) => ServerDialog(server: server),
                )
              : null,
          child: Text(server.configured ? l.serverChange : l.serverSet),
        ),
      ],
    );
  }
}

/// Type the address of the server, check it, keep it.
class ServerDialog extends StatefulWidget {
  const ServerDialog({super.key, required this.server});
  final ServerSettings server;

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  late final _url = TextEditingController(text: widget.server.url);
  bool _busy = false;
  ServerCheck? _problem;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await widget.server.save(_url.text);
    if (!mounted) return;
    if (result == ServerCheck.ok) {
      Navigator.of(context).pop();
      showFeedback(context, strings(context).serverSaved);
    } else {
      setState(() {
        _busy = false;
        _problem = result;
      });
    }
  }

  String _problemText(AppLocalizations l, ServerCheck problem) =>
      switch (problem) {
        ServerCheck.invalid => l.serverErrInvalid,
        ServerCheck.insecure => l.serverErrInsecure,
        ServerCheck.unreachable => l.serverErrUnreachable,
        ServerCheck.notErp => l.serverErrNotErp,
        ServerCheck.databaseDown => l.serverErrDatabase,
        ServerCheck.ok => '',
      };

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AlertDialog(
      title: Text(l.serverDialogTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: TextField(
                  key: const ValueKey('server-url'),
                  controller: _url,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: l.serverUrlLabel,
                    hintText: 'https://shop.example.com',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.serverChangeNote,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (_problem != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _problemText(l, _problem!),
                    key: const ValueKey('server-error'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('server-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('server-save'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? l.serverChecking : l.serverSave),
        ),
      ],
    );
  }
}
