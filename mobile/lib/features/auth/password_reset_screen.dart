import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

enum _Step { request, confirm, done }

/// Password recovery by emailed one-time code: ask for a code, then enter it
/// together with a new password. The server gives the same answer whether or not
/// the account exists.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.api,
    this.initialIdentifier = '',
  });

  final ApiClient api;
  final String initialIdentifier;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  late final _identifier = TextEditingController(
    text: widget.initialIdentifier,
  );
  final _code = TextEditingController();
  final _password = TextEditingController();
  _Step _step = _Step.request;
  bool _busy = false;
  bool _sent = false;
  ApiException? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCode() => _run(() async {
    await widget.api.post(
      '/api/v1/auth/password/reset/request/',
      body: {'identifier': _identifier.text.trim()},
      authenticated: false,
    );
    if (mounted) {
      setState(() {
        _sent = true;
        _step = _Step.confirm;
      });
    }
  });

  Future<void> _confirm() => _run(() async {
    await widget.api.post(
      '/api/v1/auth/password/reset/confirm/',
      body: {
        'identifier': _identifier.text.trim(),
        'code': _code.text.trim(),
        'new_password': _password.text,
      },
      authenticated: false,
    );
    if (mounted) setState(() => _step = _Step.done);
  });

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final generalError = _error != null && _error!.fields.isEmpty
        ? apiErrorText(l, _error!)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l.resetTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SurfaceCard(
                padding: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_step == _Step.done) ...[
                      const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(l.passwordChanged, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      GradientButton(
                        key: const ValueKey('reset-done-back'),
                        label: l.backToSignIn,
                        icon: Icons.login,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ] else ...[
                      Text(
                        l.resetIntro,
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('reset-identifier'),
                        controller: _identifier,
                        enabled: !_busy,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l.identifierLabel,
                          prefixIcon: const Icon(Icons.alternate_email),
                        ),
                      ),
                      if (_step == _Step.confirm) ...[
                        if (_sent) ...[
                          const SizedBox(height: 12),
                          Text(
                            key: const ValueKey('reset-sent'),
                            l.resetSent,
                            style: const TextStyle(
                              color: AppColors.success,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('reset-code'),
                          controller: _code,
                          enabled: !_busy,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: l.codeLabel,
                            prefixIcon: const Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('reset-new-password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: l.newPassword,
                            prefixIcon: const Icon(Icons.lock_outline),
                            errorText: fieldError(l, _error, 'new_password'),
                            errorMaxLines: 3,
                          ),
                        ),
                      ],
                      if (generalError != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            key: const ValueKey('reset-error'),
                            generalError,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_step == _Step.request) ...[
                        GradientButton(
                          key: const ValueKey('reset-send'),
                          label: l.sendCode,
                          icon: Icons.mail_outline,
                          onPressed: _busy ? null : _requestCode,
                        ),
                        TextButton(
                          key: const ValueKey('reset-have-code'),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step = _Step.confirm),
                          child: Text(l.haveCode),
                        ),
                      ] else ...[
                        GradientButton(
                          key: const ValueKey('reset-confirm'),
                          label: l.savePassword,
                          icon: Icons.check,
                          onPressed: _busy ? null : _confirm,
                        ),
                        TextButton(
                          key: const ValueKey('reset-resend'),
                          onPressed: _busy ? null : _requestCode,
                          child: Text(l.sendCode),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
