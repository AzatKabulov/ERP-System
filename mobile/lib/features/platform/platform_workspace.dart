import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import 'client_detail_screen.dart';
import 'clients_screen.dart';
import 'new_client_screen.dart';
import 'notices_screen.dart';
import 'overview_screen.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_settings_screen.dart';
import 'platform_support_screen.dart';
import '../../widgets/app_route.dart';

/// What the platform owner sees after the ordinary sign-in: the same app frame as a shop, with
/// their own pages (the overview, every client, the support desk, notices) and settings. No shop
/// is open; the server refuses these requests to anyone who is not an operator.
class PlatformWorkspace extends StatefulWidget {
  const PlatformWorkspace({
    super.key,
    required this.session,
    required this.api,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final SessionController session;
  final ApiClient api;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<PlatformWorkspace> createState() => _PlatformWorkspaceState();
}

class _PlatformWorkspaceState extends State<PlatformWorkspace> {
  late final PlatformRepository _repo = PlatformRepository(widget.api);
  AppPage _page = AppPage.platformOverview;
  String _filter = '';

  /// Bumped when something changed that the pages show, so they read it again.
  int _version = 0;

  void _go(AppPage page, {String filter = ''}) => setState(() {
    _page = page;
    _filter = filter;
  });

  Future<void> _openClient(String id, {ClientDetail? initial}) async {
    await Navigator.of(context).push<void>(
      appRoute(
        builder: (_) => ClientDetailScreen(
          repository: _repo,
          clientId: id,
          initial: initial,
        ),
      ),
    );
    // what was done there changes the counts and the lists
    if (mounted) setState(() => _version++);
  }

  Future<void> _newClient() async {
    final created = await Navigator.of(context).push<ClientDetail>(
      appRoute(builder: (_) => NewClientScreen(repository: _repo)),
    );
    if (!mounted) return;
    setState(() => _version++);
    if (created != null) await _openClient(created.row.id, initial: created);
  }

  Widget _content() => switch (_page) {
    AppPage.platformClients => ClientsScreen(
      key: ValueKey('clients-$_filter-$_version'),
      repository: _repo,
      initialFilter: _filter,
      onOpenClient: _openClient,
      onNewClient: _newClient,
    ),
    AppPage.platformSupport => PlatformSupportScreen(
      key: ValueKey('support-$_version'),
      repository: _repo,
      onOpenClient: _openClient,
    ),
    AppPage.platformNotices => NoticesScreen(repository: _repo),
    AppPage.administration => PlatformSettingsScreen(
      session: widget.session,
      repository: _repo,
      languageCode: widget.languageCode,
      onLanguageChanged: widget.onLanguageChanged,
    ),
    _ => PlatformOverviewScreen(
      key: ValueKey('overview-$_version'),
      repository: _repo,
      onOpenClient: _openClient,
      onFilter: (state) => _go(AppPage.platformClients, filter: state),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AppShell(
      pages: platformPages,
      phoneTabs: const [
        AppPage.platformOverview,
        AppPage.platformClients,
        AppPage.platformSupport,
        AppPage.platformNotices,
      ],
      page: _page,
      onNavigate: (page) => _go(page),
      body: _content(),
      languageCode: widget.languageCode,
      onLanguageChanged: widget.onLanguageChanged,
      locationControl: TopbarControl(
        key: const ValueKey('platform-label'),
        icon: AppIcons.shield,
        text: l.pfPlatform,
      ),
      userName: widget.session.user?.displayName ?? '',
      roleName: l.pfOwnerRole,
      onSignOut: widget.session.signOut,
    );
  }
}
