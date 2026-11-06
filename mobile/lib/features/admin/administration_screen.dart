import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../shared/async_section.dart';
import '../catalog/catalog_repository.dart';
import 'admin_repository.dart';
import 'exchange_rate_section.dart';

String roleLabel(AppLocalizations l, String role) => switch (role) {
  'owner' => l.roleOwner,
  'manager' => l.roleManager,
  'sales' => l.roleSales,
  'warehouse' => l.roleWarehouse,
  _ => role,
};

String kindLabel(AppLocalizations l, String kind) =>
    kind == 'warehouse' ? l.kindWarehouse : l.kindStore;

/// Settings for the signed-in business: language, business profile, locations and
/// staff. Each section loads on its own and shows only what the role may see; the
/// server enforces the same rules on every request.
class RealAdministrationScreen extends StatefulWidget {
  const RealAdministrationScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.catalog,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final SessionController session;
  final AdminRepository repository;
  final CatalogRepository catalog;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<RealAdministrationScreen> createState() =>
      _RealAdministrationScreenState();
}

class _RealAdministrationScreenState extends State<RealAdministrationScreen> {
  final _locations = GlobalKey<AsyncSectionState<List<LocationRecord>>>();
  final _staff = GlobalKey<AsyncSectionState<List<StaffRecord>>>();
  final _business = GlobalKey<AsyncSectionState<BusinessInfo>>();

  AdminRepository get repo => widget.repository;
  SessionController get session => widget.session;

  Future<void> _locationsChanged() async {
    _locations.currentState?.reload();
    _staff.currentState?.reload();
    await session.refreshProfile(); // the header location picker follows
  }

  _SettingsTab _tab = _SettingsTab.account;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768; // padding only
    final tabs = <(_SettingsTab, String)>[
      (_SettingsTab.account, l.settingsTabAccount),
      if (session.can('business.view') ||
          session.can('exchange_rate.view') ||
          session.can('location.view'))
        (_SettingsTab.shop, l.settingsTabShop),
      if (session.can('staff.view')) (_SettingsTab.team, l.staffTitle),
    ];
    final tab = tabs.any((t) => t.$1 == _tab) ? _tab : _SettingsTab.account;
    // A plain scrolling column (not a lazy list): the page is short, and every
    // section should exist for accessibility tools and tests alike.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 32,
        narrow ? 20 : 32,
        narrow ? 16 : 32,
        40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: l.administration,
            subtitle: session.membership?.businessName,
          ),
          const SizedBox(height: 24),
          if (tabs.length > 1) ...[
            AppTabs<_SettingsTab>(
              keyPrefix: 'settings-tab',
              keyName: (t) => t.name,
              tabs: tabs,
              value: tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 24),
          ],
          // the sections slide in softly instead of snapping
          AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.base),
            switchInCurve: AppMotion.arrive,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: Align(
              key: ValueKey(tab),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: switch (tab) {
                  _SettingsTab.account => _account(context),
                  _SettingsTab.shop => _shop(context),
                  _SettingsTab.team => _team(context),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The person: who is signed in, the interface language, and signing out.
  Widget _account(BuildContext context) {
    final l = strings(context);
    final user = session.user;
    final membership = session.membership;
    final name = user?.displayName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppGradients.spotlight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user != null)
                      Text(
                        l.signedInAs(user.displayName),
                        key: const ValueKey('signed-in-as'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    if (membership != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${roleLabel(l, membership.role)} · ${membership.businessName}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(l.language),
              const SizedBox(height: 4),
              Text(
                l.languageHint,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              AppSegmented<String>(
                keyPrefix: 'language-chip',
                options: [('ru', l.languageRussian), ('tk', l.languageTurkmen)],
                value: widget.languageCode,
                onChanged: widget.onLanguageChanged,
              ),
              const SizedBox(height: 12),
              Text(
                l.translationsPending,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Signing out sits by itself at the bottom, away from the settings it must not be
        // confused with.
        SurfaceCard(
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.signOutTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.signOutHint,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('admin-sign-out'),
                onPressed: session.signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: Color(0xFFF3C9C5)),
                ),
                icon: const AppIcon(AppIcons.logout),
                label: Text(l.signOut),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The shop: its details, the exchange rate and the name of its place. One business is one
  /// shop (its warehouse is its back room), so a place cannot be added here.
  Widget _shop(BuildContext context) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.can('business.view'))
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(l.adminBusinessProfile),
                const SizedBox(height: 12),
                AsyncSection<BusinessInfo>(
                  key: _business,
                  load: repo.business,
                  builder: (context, info) => _BusinessForm(
                    info: info,
                    canEdit: session.can('business.manage'),
                    repository: repo,
                    // The form already shows what was saved; reloading it would
                    // discard its confirmation. Only the header needs refreshing.
                    onSaved: session.refreshProfile,
                  ),
                ),
              ],
            ),
          ),
        if (session.can('exchange_rate.view')) ...[
          const SizedBox(height: 16),
          ExchangeRateSection(
            repository: widget.catalog,
            canManage: session.can('exchange_rate.manage'),
          ),
        ],
        if (session.can('location.view')) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(l.shopPlaceTitle),
                const SizedBox(height: 4),
                Text(
                  l.shopPlaceHint,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                AsyncSection<List<LocationRecord>>(
                  key: _locations,
                  load: () => repo.locations(),
                  builder: (context, items) => Column(
                    children: [
                      for (final item in items.where((i) => i.isActive))
                        ListTile(
                          key: ValueKey('location-${item.name}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const AppIcon(
                            AppIcons.stock,
                            color: AppColors.blue,
                          ),
                          title: Text(item.name),
                          subtitle: Text(kindLabel(l, item.kind)),
                          trailing: session.can('location.manage')
                              ? IconButton(
                                  key: ValueKey('edit-location-${item.name}'),
                                  tooltip: l.editLocation,
                                  icon: const AppIcon(AppIcons.edit),
                                  onPressed: () async {
                                    if (await showLocationDialog(
                                          context,
                                          repo,
                                          existing: item,
                                        ) ==
                                        true) {
                                      await _locationsChanged();
                                    }
                                  },
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The people who work in the shop and what each may do.
  Widget _team(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            l.staffTitle,
            action: session.can('staff.manage')
                ? OutlinedButton.icon(
                    key: const ValueKey('add-staff'),
                    onPressed: () async {
                      if (await showStaffDialog(context, repo) == true) {
                        _staff.currentState?.reload();
                      }
                    },
                    icon: const AppIcon(AppIcons.personAdd),
                    label: Text(l.addStaff),
                  )
                : null,
          ),
          AsyncSection<List<StaffRecord>>(
            key: _staff,
            load: repo.staff,
            builder: (context, items) => Column(
              children: [
                for (final member in items)
                  ListTile(
                    key: ValueKey('staff-${member.username}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const AppIcon(
                      AppIcons.user,
                      color: AppColors.blue,
                    ),
                    title: Text(
                      member.userId == session.user?.id
                          ? '${member.displayName} (${l.staffYou})'
                          : member.displayName,
                    ),
                    subtitle: Text(
                      '${member.username} · ${roleLabel(l, member.role)}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!member.isActive)
                          StatusPill(
                            label: l.membershipInactive,
                            warning: true,
                          ),
                        if (session.can('staff.manage'))
                          IconButton(
                            key: ValueKey('edit-staff-${member.username}'),
                            tooltip: l.editStaff,
                            icon: const AppIcon(AppIcons.edit),
                            onPressed: () async {
                              if (await showStaffDialog(
                                    context,
                                    repo,
                                    existing: member,
                                  ) ==
                                  true) {
                                _staff.currentState?.reload();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SettingsTab { account, shop, team }

/// The time zones a shop is likely to use: the receipts and the reports read the shop's day and
/// hour in this zone. (Any other zone already stored stays selectable.)
const _timezones = <String, String>{
  'Asia/Ashgabat': 'Ашхабад · Asia/Ashgabat (UTC+5)',
  'Asia/Kuala_Lumpur': 'Куала-Лумпур · Asia/Kuala_Lumpur (UTC+8)',
  'Europe/Moscow': 'Москва · Europe/Moscow (UTC+3)',
  'Europe/Istanbul': 'Стамбул · Europe/Istanbul (UTC+3)',
  'Asia/Dubai': 'Дубай · Asia/Dubai (UTC+4)',
  'Asia/Tashkent': 'Ташкент · Asia/Tashkent (UTC+5)',
  'Asia/Almaty': 'Алматы · Asia/Almaty (UTC+5)',
  'UTC': 'UTC',
};

class _BusinessForm extends StatefulWidget {
  const _BusinessForm({
    required this.info,
    required this.canEdit,
    required this.repository,
    required this.onSaved,
  });
  final BusinessInfo info;
  final bool canEdit;
  final AdminRepository repository;
  final Future<void> Function() onSaved;

  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  late final _name = TextEditingController(text: widget.info.name);
  late final _address = TextEditingController(text: widget.info.address);
  late final _phone = TextEditingController(text: widget.info.phone);
  late String _defaultLanguage = widget.info.defaultLanguage;
  late String _documentLanguage = widget.info.documentLanguage;
  late String _timezone = widget.info.timezone;
  bool _busy = false;
  bool _saved = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await widget.repository.updateBusiness(
        name: _name.text.trim(),
        defaultLanguage: _defaultLanguage,
        documentLanguage: _documentLanguage,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        timezone: _timezone,
      );
      await widget.onSaved();
      if (mounted) setState(() => _saved = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final enabled = widget.canEdit && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          label: l.businessName,
          child: TextField(
            key: const ValueKey('business-name'),
            controller: _name,
            enabled: enabled,
            decoration: InputDecoration(
              errorText: fieldError(l, _error, 'name'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: l.businessAddress,
          child: TextField(
            key: const ValueKey('business-address'),
            controller: _address,
            enabled: enabled,
            decoration: InputDecoration(
              errorText: fieldError(l, _error, 'address'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: l.businessPhone,
          child: TextField(
            key: const ValueKey('business-phone'),
            controller: _phone,
            enabled: enabled,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              helperText: l.businessDocumentNote,
              helperMaxLines: 2,
              errorText: fieldError(l, _error, 'phone'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _LanguageDropdown(
              label: l.defaultLanguageLabel,
              value: _defaultLanguage,
              enabled: enabled,
              onChanged: (v) => setState(() => _defaultLanguage = v),
              fieldKey: const ValueKey('business-default-language'),
            ),
            _LanguageDropdown(
              label: l.documentLanguage,
              value: _documentLanguage,
              enabled: enabled,
              onChanged: (v) => setState(() => _documentLanguage = v),
              fieldKey: const ValueKey('business-document-language'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('${l.currencyLabel}: ${widget.info.currency}'),
        const SizedBox(height: 4),
        Text(
          l.currencyFixedNote,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: LabeledField(
            label: l.timezoneLabel,
            child: DropdownButtonFormField<String>(
              key: const ValueKey('business-timezone'),
              isExpanded: true,
              initialValue: _timezone,
              decoration: const InputDecoration(),
              items: [
                for (final zone in {
                  ..._timezones.keys,
                  _timezone, // a zone set some other way stays selectable
                })
                  DropdownMenuItem(
                    value: zone,
                    child: Text(
                      _timezones[zone] ?? zone,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (v) => setState(() => _timezone = v ?? _timezone)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.timezoneHint,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (_error != null && _error!.fields.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            apiErrorText(l, _error!),
            style: const TextStyle(color: AppColors.danger),
          ),
        ],
        if (_saved) ...[
          const SizedBox(height: 12),
          Text(
            l.saved,
            key: const ValueKey('business-saved'),
            style: const TextStyle(color: AppColors.success),
          ),
        ],
        if (widget.canEdit) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            key: const ValueKey('business-save'),
            label: l.save,
            icon: AppIcons.check,
            onPressed: _busy ? null : _save,
          ),
        ],
      ],
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.fieldKey,
  });
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      child: LabeledField(
        label: label,
        child: DropdownButtonFormField<String>(
          key: fieldKey,
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(),
          items: [
            DropdownMenuItem(value: 'ru', child: Text(l.languageRussian)),
            DropdownMenuItem(value: 'tk', child: Text(l.languageTurkmen)),
          ],
          onChanged: enabled ? (v) => onChanged(v ?? value) : null,
        ),
      ),
    );
  }
}

/// Add or edit a location. Returns true when something was saved.
Future<bool?> showLocationDialog(
  BuildContext context,
  AdminRepository repository, {
  LocationRecord? existing,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _LocationDialog(repository: repository, existing: existing),
);

class _LocationDialog extends StatefulWidget {
  const _LocationDialog({required this.repository, this.existing});
  final AdminRepository repository;
  final LocationRecord? existing;

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _kind = widget.existing?.kind ?? 'store';
  late bool _active = widget.existing?.isActive ?? true;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createLocation(
          name: _name.text.trim(),
          kind: _kind,
        );
      } else {
        await widget.repository.updateLocation(
          existing.id,
          name: _name.text.trim(),
          kind: _kind,
          isActive: _active,
        );
      }
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
    return AlertDialog(
      title: Text(widget.existing == null ? l.addLocation : l.editLocation),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LabeledField(
                label: l.locationName,
                child: TextField(
                  key: const ValueKey('location-name'),
                  controller: _name,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    errorText: fieldError(l, _error, 'name'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: l.locationKind,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('location-kind'),
                  initialValue: _kind,
                  decoration: InputDecoration(),
                  items: [
                    DropdownMenuItem(value: 'store', child: Text(l.kindStore)),
                    DropdownMenuItem(
                      value: 'warehouse',
                      child: Text(l.kindWarehouse),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _kind = v ?? _kind),
                ),
              ),
              if (widget.existing != null)
                SwitchListTile(
                  key: const ValueKey('location-active'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_active ? l.activate : l.deactivate),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
              if (_error != null && _error!.fields.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  apiErrorText(l, _error!),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('location-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Add or edit a staff member. Returns true when something was saved.
Future<bool?> showStaffDialog(
  BuildContext context,
  AdminRepository repository, {
  StaffRecord? existing,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _StaffDialog(repository: repository, existing: existing),
);

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({required this.repository, this.existing});
  final AdminRepository repository;
  final StaffRecord? existing;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final _username = TextEditingController();
  late final _email = TextEditingController();
  late final _fullName = TextEditingController();
  late final _password = TextEditingController();
  late String _role = widget.existing?.role ?? 'sales';
  late String _language = widget.existing?.preferredLanguage ?? 'ru';
  late bool _all = widget.existing?.allLocations ?? false;
  late bool _active = widget.existing?.isActive ?? true;
  late final Set<String> _locationIds = {...?widget.existing?.locationIds};
  List<LocationRecord> _available = const [];
  bool _busy = false;
  bool _codeSent = false;
  ApiException? _error;

  bool get _editing => widget.existing != null;
  bool get _restricted => _role == 'sales' || _role == 'warehouse';

  @override
  void initState() {
    super.initState();
    widget.repository.locations().then((items) {
      if (mounted) setState(() => _available = items);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    for (final c in [_username, _email, _fullName, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ids = _locationIds.toList();
      if (_editing) {
        await widget.repository.updateStaff(
          widget.existing!.id,
          role: _role,
          allLocations: _restricted ? _all : false,
          locationIds: _restricted ? ids : <String>[],
          isActive: _active,
        );
      } else {
        await widget.repository.createStaff(
          username: _username.text.trim(),
          email: _email.text.trim(),
          fullName: _fullName.text.trim(),
          preferredLanguage: _language,
          role: _role,
          allLocations: _restricted ? _all : false,
          locationIds: _restricted ? ids : <String>[],
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.sendResetCode(widget.existing!.id);
      if (mounted) setState(() => _codeSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return AlertDialog(
      title: Text(_editing ? l.editStaff : l.addStaff),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${widget.existing!.displayName} · ${widget.existing!.username}',
                  ),
                )
              else ...[
                LabeledField(
                  label: l.username,
                  child: TextField(
                    key: const ValueKey('staff-username'),
                    controller: _username,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: InputDecoration(
                      errorText: fieldError(l, _error, 'username'),
                      errorMaxLines: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: l.emailLabel,
                  child: TextField(
                    key: const ValueKey('staff-email'),
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      errorText: fieldError(l, _error, 'email'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: l.fullNameLabel,
                  child: TextField(
                    key: const ValueKey('staff-full-name'),
                    controller: _fullName,
                    enabled: !_busy,
                    decoration: InputDecoration(),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: l.language,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('staff-language'),
                    initialValue: _language,
                    decoration: InputDecoration(),
                    items: [
                      DropdownMenuItem(
                        value: 'ru',
                        child: Text(l.languageRussian),
                      ),
                      DropdownMenuItem(
                        value: 'tk',
                        child: Text(l.languageTurkmen),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _language = v ?? _language),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              LabeledField(
                label: l.roleLabel,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('staff-role'),
                  initialValue: _role,
                  decoration: InputDecoration(),
                  items: [
                    for (final role in const [
                      'owner',
                      'manager',
                      'sales',
                      'warehouse',
                    ])
                      DropdownMenuItem(
                        value: role,
                        child: Text(roleLabel(l, role)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _role = v ?? _role),
                ),
              ),
              if (_restricted) ...[
                SwitchListTile(
                  key: const ValueKey('staff-all-locations'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.allLocationsLabel),
                  value: _all,
                  onChanged: _busy ? null : (v) => setState(() => _all = v),
                ),
                if (!_all) ...[
                  Text(
                    l.pickLocations,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  for (final location in _available)
                    CheckboxListTile(
                      key: ValueKey('staff-location-${location.name}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(location.name),
                      value: _locationIds.contains(location.id),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _locationIds.add(location.id);
                              } else {
                                _locationIds.remove(location.id);
                              }
                            }),
                    ),
                  if (fieldError(l, _error, 'locations') != null)
                    Text(
                      fieldError(l, _error, 'locations')!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
              if (_editing)
                SwitchListTile(
                  key: const ValueKey('staff-active'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_active ? l.activate : l.deactivate),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                )
              else ...[
                const SizedBox(height: 12),
                LabeledField(
                  label: l.initialPasswordLabel,
                  child: TextField(
                    key: const ValueKey('staff-password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: InputDecoration(
                      helperText: l.initialPasswordHint,
                      helperMaxLines: 3,
                      errorText: fieldError(l, _error, 'password'),
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ],
              if (_editing) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('staff-send-code'),
                  onPressed: _busy ? null : _sendCode,
                  icon: const AppIcon(AppIcons.mail),
                  label: Text(l.sendResetCode),
                ),
                if (_codeSent)
                  Text(
                    l.resetCodeRequested,
                    key: const ValueKey('staff-code-sent'),
                    style: const TextStyle(color: AppColors.success),
                  ),
              ],
              if (_error != null && _error!.fields.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  apiErrorText(l, _error!),
                  key: const ValueKey('staff-error'),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('staff-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
