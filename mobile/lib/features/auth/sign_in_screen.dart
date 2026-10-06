import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
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
    required this.configured,
  });

  final SessionController session;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  /// False when this build has no server address.
  final bool configured;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
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
                          if (!widget.configured)
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
                            onPressed: _busy || !widget.configured
                                ? null
                                : _submit,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            key: const ValueKey('forgot-password'),
                            onPressed: _busy || !widget.configured
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
