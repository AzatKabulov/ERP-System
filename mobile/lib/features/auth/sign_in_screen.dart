import 'package:flutter/material.dart';
import '../../widgets/pwa_viewport.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/config/server_settings.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import 'password_form.dart';
import 'password_reset_screen.dart';
import '../../widgets/app_route.dart';

/// A build made with `--dart-define=ROLE_PICKER=true` signs in by choosing a role and then typing
/// that account's password (the usernames are the role names). Plain password sign-in stays one
/// tap away; the server's rules do not change.
bool rolePicker = const bool.fromEnvironment('ROLE_PICKER');

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
  List<String> _testRoles = const [];
  int _probeId = 0;
  bool _usePassword = false;
  static const _allRoles = ['owner', 'manager', 'sales', 'warehouse'];
  bool get _hasRoleChoice => _testRoles.isNotEmpty || rolePicker;
  bool get _roleMode => _hasRoleChoice && !_usePassword;
  void _serverChanged() {
    setState(() {
      _error = null;
      _testRoles = const [];
    });
    _probeTestLogin();
  }

  Future<void> _probeTestLogin() async {
    final id = ++_probeId;
    if (!widget.server.configured) return;
    try {
      final data = (await widget.session.api.send(
        'GET',
        '/api/v1/health/',
        authenticated: false,
      )).map;
      if (!mounted || id != _probeId) return;
      const allowed = ['owner', 'manager', 'sales', 'warehouse', 'platform'];
      setState(
        () => _testRoles = [
          for (final role in allowed)
            if ((data['test_login_roles'] as List?)?.contains(role) == true)
              role,
        ],
      );
    } catch (_) {
      /* Ordinary sign-in remains usable when the optional probe fails. */
    }
  }

  @override
  void initState() {
    super.initState();
    widget.server.addListener(_serverChanged);
    _probeTestLogin();
  }

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  /// The platform owner's account is asked for the code from their authenticator app after the
  /// password; the server says so (`otp_required`) and only then does the field appear.
  bool _needsCode = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    widget.server.removeListener(_serverChanged);
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // never two sign-in requests at once
    final username = _username.text.trim();
    if (_roleMode) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final l = strings(context);
        final role = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(l.testLoginChooseRole),
            children: [
              for (final role in _testRoles.isNotEmpty ? _testRoles : _allRoles)
                SimpleDialogOption(
                  key: ValueKey('test-login-$role'),
                  onPressed: () => Navigator.of(context).pop(role),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(switch (role) {
                      'owner' => l.roleOwner,
                      'manager' => l.roleManager,
                      'sales' => l.roleSales,
                      'platform' => l.pfOwnerRole,
                      _ => l.roleWarehouse,
                    }),
                  ),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.cancel),
              ),
            ],
          ),
        );
        if (mounted && role != null) {
          if (_testRoles.isNotEmpty) {
            await widget.session.signInAsTestRole(role);
          } else {
            final password = await _askPassword(role);
            if (mounted && password != null) {
              await widget.session.signIn(role, password);
            }
          }
        }
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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
    if (_needsCode && _code.text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = const ApiException(
          kind: ApiErrorKind.client,
          code: 'validation_error',
        );
      });
      _codeFocus.requestFocus();
      return;
    }
    try {
      await widget.session.signIn(
        username,
        _password.text,
        otpToken: _needsCode ? _code.text.trim() : null,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'otp_required') {
        // not an error: the password was right, one more step is needed
        setState(() {
          _needsCode = true;
          _error = null;
        });
        _codeFocus.requestFocus();
      } else {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(String role) {
    final l = strings(context);
    final controller = TextEditingController();
    final name = switch (role) {
      'owner' => l.roleOwner,
      'manager' => l.roleManager,
      'sales' => l.roleSales,
      _ => l.roleWarehouse,
    };
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.roleLoginPasswordTitle(name)),
        content: TextField(
          key: const ValueKey('role-login-password'),
          controller: controller,
          autofocus: true,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(labelText: l.password),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.cancel),
          ),
          TextButton(
            key: const ValueKey('role-login-submit'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l.signInAction),
          ),
        ],
      ),
    );
  }

  Widget _languageSwitch({bool expand = false}) => AppSegmented<String>(
    expand: expand,
    key: const ValueKey('language-selector'),
    keyPrefix: 'language',
    options: const [('ru', 'RU'), ('tk', 'TM')],
    value: widget.languageCode,
    onChanged: widget.onLanguageChanged,
  );

  Widget _form(AppLocalizations l) {
    final session = widget.session;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _languageSwitch(expand: true),
          const SizedBox(height: 18),
          Text(l.signInTitle, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            l.signInSubtitle,
            style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          if (_testRoles.isNotEmpty) _Notice(text: l.testLoginNotice),
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
          if (!_roleMode) ...[
            if (session.recentUsernames.isNotEmpty) ...[
              Text(
                l.recentSignIns,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in session.recentUsernames)
                    AppPill(
                      key: ValueKey('recent-$name'),
                      label: name,
                      icon: AppIcons.user,
                      selected: _username.text.trim().toLowerCase() == name,
                      onTap: _busy
                          ? null
                          : () {
                              setState(() => _username.text = name);
                              _passwordFocus.requestFocus();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            LabeledField(
              label: l.username,
              child: TextField(
                key: const ValueKey('sign-in-username'),
                controller: _username,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: AppIcon(AppIcons.user, size: 20),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PasswordField(
              key: const ValueKey('sign-in-password'),
              label: l.password,
              controller: _password,
              focusNode: _passwordFocus,
              enabled: !_busy,
              textInputAction: _needsCode
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: (_) =>
                  _needsCode ? _codeFocus.requestFocus() : _submit(),
            ),
            if (_needsCode) ...[
              const SizedBox(height: 18),
              LabeledField(
                label: l.signInCodeLabel,
                child: TextField(
                  key: const ValueKey('sign-in-code'),
                  controller: _code,
                  focusNode: _codeFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  maxLength: 8,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    counterText: '',
                    helperText: l.signInCodeHint,
                    helperMaxLines: 2,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: AppIcon(AppIcons.lock, size: 20),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 48),
                  ),
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                key: const ValueKey('sign-in-error'),
                apiErrorText(l, _error!),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!_roleMode)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('forgot-password'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: _busy || !widget.server.configured
                    ? null
                    : () => Navigator.of(context).push(
                        appRoute<void>(
                          builder: (_) => PasswordResetScreen(
                            api: widget.session.api,
                            initialIdentifier: _username.text.trim(),
                          ),
                        ),
                      ),
                child: Text(l.forgotPassword),
              ),
            ),
          if (_hasRoleChoice)
            TextButton(
              key: const ValueKey('test-login-toggle'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _usePassword = !_usePassword;
                      _error = null;
                    }),
              child: Text(
                _roleMode
                    ? l.testLoginUsePassword
                    : _testRoles.isNotEmpty
                    ? l.testLoginUseRole
                    : l.roleLoginUseRole,
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            key: const ValueKey('sign-in-submit'),
            label: _busy ? l.signingIn : l.signInAction,
            trailingIcon: AppIcons.arrow,
            onPressed: _busy || !widget.server.configured ? null : _submit,
          ),
          if (!widget.server.fixed) ...[
            const Divider(height: 40),
            _ServerLine(server: widget.server, enabled: !_busy),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        // In /fs/, the brand paints beneath the clock; only its controls inset.
        top: !PwaAreas.enabledOf(context),
        left: !PwaAreas.enabledOf(context),
        right: !PwaAreas.enabledOf(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 768;
            final form = Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 40 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  // on a wide screen the form sits on a pane of glass over the soft light
                  child: FadeUp(
                    child: GlassSurface(
                      radius: AppRadius.dialog + 6,
                      blur: 26,
                      padding: const EdgeInsets.all(32),
                      child: _form(l),
                    ),
                  ),
                ),
              ),
            );
            if (!wide) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BrandPanel(l: l, compact: true),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      child: _form(l),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(flex: 9, child: _BrandPanel(l: l, compact: false)),
                  Expanded(flex: 11, child: form),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The deep side of the sign-in page: the wordmark, one large line and a short caption on the
/// navy-to-cobalt gradient, lit by two soft glows.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.l, required this.compact});
  final AppLocalizations l;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = compact
        ? const BorderRadius.vertical(bottom: Radius.circular(28))
        : BorderRadius.circular(28);
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        key: const ValueKey('sign-in-brand-panel'),
        constraints: BoxConstraints(minHeight: compact ? 220 : 0),
        decoration: BoxDecoration(
          gradient: AppGradients.spotlight,
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: compact
              ? _content(context)
              : SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: _content(context)),
                  ),
                ),
        ),
      ),
    );
  }

  static Widget _glow(double size, int argb) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [Color(argb), Color(argb & 0x00FFFFFF)]),
    ),
  );

  Widget _content(BuildContext context) {
    final safe = compact && PwaAreas.enabledOf(context)
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: ExcludeSemantics(child: _glow(380, 0x663D63FF)),
        ),
        Positioned(
          bottom: -170,
          left: -90,
          child: ExcludeSemantics(child: _glow(420, 0x446A4DFF)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            (compact ? 24 : 40) + safe.left,
            (compact ? 24 : 40) + safe.top,
            (compact ? 24 : 40) + safe.right,
            compact ? 24 : 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BrandMark(l.appName.characters.first.toUpperCase()),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      l.appName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.onInverse,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 28 : 48),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  l.brandTagline,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 30 : 52,
                    height: 1.1,
                    letterSpacing: compact ? -0.9 : -1.6,
                    color: AppColors.onInverse,
                  ),
                ),
              ),
              SizedBox(height: compact ? 20 : 48),
              Text(
                l.brandFoot,
                style: const TextStyle(
                  color: AppColors.onInverseMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: NoticeBanner(text: text, action: action),
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
          style: TextStyle(color: AppColors.muted, fontSize: 13),
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
                child: LabeledField(
                  label: l.serverUrlLabel,
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
                      hintText: 'https://shop.example.com',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.serverChangeNote,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (_problem != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _problemText(l, _problem!),
                    key: const ValueKey('server-error'),
                    style: TextStyle(color: AppColors.danger),
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
