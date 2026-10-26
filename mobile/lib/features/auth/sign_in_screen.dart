import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

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
  List<String> _testRoles = const [];
  int _probeId = 0;
  bool _usePassword = false;
  bool get _roleMode => _testRoles.isNotEmpty && !_usePassword;
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
      const allowed = ['owner', 'manager', 'sales', 'warehouse'];
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
              for (final role in _testRoles)
                SimpleDialogOption(
                  key: ValueKey('test-login-$role'),
                  onPressed: () => Navigator.of(context).pop(role),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(switch (role) {
                      'owner' => l.roleOwner,
                      'manager' => l.roleManager,
                      'sales' => l.roleSales,
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
          await widget.session.signInAsTestRole(role);
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
    try {
      await widget.session.signIn(username, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.5,
            ),
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
            LabeledField(
              label: l.password,
              child: TextField(
                key: const ValueKey('sign-in-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: AppIcon(AppIcons.lock, size: 20),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48),
                ),
              ),
            ),
          ],
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
                        MaterialPageRoute<void>(
                          builder: (_) => PasswordResetScreen(
                            api: widget.session.api,
                            initialIdentifier: _username.text.trim(),
                          ),
                        ),
                      ),
                child: Text(l.forgotPassword),
              ),
            ),
          if (_testRoles.isNotEmpty)
            TextButton(
              key: const ValueKey('test-login-toggle'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _usePassword = !_usePassword;
                      _error = null;
                    }),
              child: Text(
                _roleMode ? l.testLoginUsePassword : l.testLoginUseRole,
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
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 768;
            final form = Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 40 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: FadeUp(child: _form(l)),
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
        ? const BorderRadius.vertical(bottom: Radius.circular(18))
        : BorderRadius.circular(18);
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        constraints: BoxConstraints(minHeight: compact ? 220 : 0),
        decoration: BoxDecoration(
          gradient: AppGradients.spotlight,
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: compact
              ? _content()
              : SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: _content()),
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

  Widget _content() {
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
          padding: EdgeInsets.all(compact ? 24 : 40),
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
