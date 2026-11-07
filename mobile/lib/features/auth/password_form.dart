import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';

/// A password box with an eye to look at what was typed (a mistyped password is the commonest
/// reason a person is locked out, and a phone keyboard makes typos easy).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.autofillHint = AutofillHints.password,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final String? helperText;
  final String autofillHint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return LabeledField(
      label: widget.label,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: !_shown,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [widget.autofillHint],
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          errorText: widget.errorText,
          helperText: widget.helperText,
          helperMaxLines: 3,
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: AppIcon(AppIcons.lock, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          suffixIcon: IconButton(
            tooltip: _shown ? l.hidePassword : l.showPassword,
            icon: AppIcon(
              _shown ? AppIcons.eyeOff : AppIcons.eye,
              size: 20,
              color: AppColors.muted,
            ),
            onPressed: widget.enabled
                ? () => setState(() => _shown = !_shown)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Choosing a new password: the current one (unless it was just typed), the new one twice, one
/// button. Used by the forced "choose your own" screen and by Settings.
class PasswordChangeForm extends StatefulWidget {
  const PasswordChangeForm({
    super.key,
    required this.session,
    required this.onDone,
    this.currentKnown,
    this.submitLabel,
  });

  final SessionController session;

  /// The password typed a moment ago to sign in, if there is one: then it is not asked again.
  final String? currentKnown;
  final VoidCallback onDone;
  final String? submitLabel;

  @override
  State<PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends State<PasswordChangeForm> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  ApiException? _error;
  String? _newError;
  String? _repeatError;

  bool get _askCurrent => widget.currentKnown == null;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = strings(context);
    final fresh = _new.text;
    setState(() {
      _error = null;
      _newError = null;
      _repeatError = null;
      if (_askCurrent && _current.text.isEmpty) {
        _error = const ApiException(
          kind: ApiErrorKind.client,
          code: 'invalid_old_password',
        );
      }
      if (fresh.length < 10) {
        _newError = l.passwordTooShort;
      } else if (_repeat.text != fresh) {
        _repeatError = l.passwordMismatch;
      }
    });
    if (_error != null || _newError != null || _repeatError != null) return;
    setState(() => _busy = true);
    try {
      await widget.session.changePassword(
        widget.currentKnown ?? _current.text,
        fresh,
      );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _repeat.clear();
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final error = _error;
    final wrongCurrent =
        error != null &&
        (error.code == 'invalid_old_password' ||
            error.fieldCode('old_password') != null);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_askCurrent) ...[
            PasswordField(
              key: const ValueKey('password-current'),
              label: l.currentPasswordLabel,
              controller: _current,
              enabled: !_busy,
              errorText: wrongCurrent ? l.errorInvalidOldPassword : null,
            ),
            const SizedBox(height: 16),
          ],
          PasswordField(
            key: const ValueKey('password-new'),
            label: l.newPassword,
            controller: _new,
            enabled: !_busy,
            autofillHint: AutofillHints.newPassword,
            helperText: l.passwordRulesHint,
            errorText: _newError ?? fieldError(l, error, 'new_password'),
          ),
          const SizedBox(height: 16),
          PasswordField(
            key: const ValueKey('password-repeat'),
            label: l.repeatPasswordLabel,
            controller: _repeat,
            enabled: !_busy,
            autofillHint: AutofillHints.newPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            errorText: _repeatError,
          ),
          if (error != null &&
              !wrongCurrent &&
              error.fieldCode('new_password') == null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                key: const ValueKey('password-error'),
                apiErrorText(l, error),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            key: const ValueKey('password-submit'),
            label: widget.submitLabel ?? l.changePasswordTitle,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// The screen a person sees right after signing in with a password somebody else chose (the
/// owner for a seller, us for a new shop's owner). Nothing else opens until they choose their
/// own.
class ChoosePasswordScreen extends StatelessWidget {
  const ChoosePasswordScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: FadeUp(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.tint,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.lock,
                            size: 24,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l.choosePasswordTitle,
                      key: const ValueKey('choose-password-title'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.choosePasswordIntro,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    PasswordChangeForm(
                      session: session,
                      currentKnown: session.enteredPassword,
                      submitLabel: l.savePassword,
                      onDone: () {},
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const ValueKey('choose-password-sign-out'),
                      onPressed: session.signOut,
                      child: Text(l.signOut),
                    ),
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
