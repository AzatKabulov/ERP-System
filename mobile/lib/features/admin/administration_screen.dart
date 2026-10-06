import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'admin_repository.dart';

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
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final SessionController session;
  final AdminRepository repository;
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

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final user = session.user;
    // A plain scrolling column (not a lazy list): the page is short, and every
    // section should exist for accessibility tools and tests alike.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(l.preferences),
                const SizedBox(height: 16),
                if (user != null)
                  Text(
                    l.signedInAs(user.displayName),
                    key: const ValueKey('signed-in-as'),
                  ),
                const SizedBox(height: 16),
                Text(
                  l.language,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('language-chip-ru'),
                      label: Text(l.languageRussian),
                      selected: widget.languageCode == 'ru',
                      onSelected: (_) => widget.onLanguageChanged('ru'),
                    ),
                    ChoiceChip(
                      key: const ValueKey('language-chip-tk'),
                      label: Text(l.languageTurkmen),
                      selected: widget.languageCode == 'tk',
                      onSelected: (_) => widget.onLanguageChanged('tk'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('admin-sign-out'),
                  onPressed: session.signOut,
                  icon: const Icon(Icons.logout),
                  label: Text(l.signOut),
                ),
                const SizedBox(height: 12),
                Text(
                  l.translationsPending,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
          if (session.can('business.view')) ...[
            const SizedBox(height: 24),
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
          ],
          if (session.can('location.view')) ...[
            const SizedBox(height: 24),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    l.locations,
                    action: session.can('location.manage')
                        ? OutlinedButton.icon(
                            key: const ValueKey('add-location'),
                            onPressed: () async {
                              if (await showLocationDialog(context, repo) ==
                                  true) {
                                await _locationsChanged();
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: Text(l.addLocation),
                          )
                        : null,
                  ),
                  AsyncSection<List<LocationRecord>>(
                    key: _locations,
                    load: () => repo.locations(
                      includeInactive: session.can('location.manage'),
                    ),
                    builder: (context, items) => Column(
                      children: [
                        for (final item in items)
                          ListTile(
                            key: ValueKey('location-${item.name}'),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.kind == 'warehouse'
                                  ? Icons.warehouse_outlined
                                  : Icons.storefront_outlined,
                              color: AppColors.blue,
                            ),
                            title: Text(item.name),
                            subtitle: Text(kindLabel(l, item.kind)),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (!item.isActive)
                                  StatusPill(
                                    label: l.inactiveLabel,
                                    warning: true,
                                  ),
                                if (session.can('location.manage'))
                                  IconButton(
                                    key: ValueKey('edit-location-${item.name}'),
                                    tooltip: l.editLocation,
                                    icon: const Icon(Icons.edit_outlined),
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
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (session.can('staff.view')) ...[
            const SizedBox(height: 24),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    l.staffTitle,
                    action: session.can('staff.manage')
                        ? OutlinedButton.icon(
                            key: const ValueKey('add-staff'),
                            onPressed: () async {
                              if (await showStaffDialog(context, repo) ==
                                  true) {
                                _staff.currentState?.reload();
                              }
                            },
                            icon: const Icon(Icons.person_add_alt),
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
                            leading: const Icon(
                              Icons.person_outline,
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
                                    key: ValueKey(
                                      'edit-staff-${member.username}',
                                    ),
                                    tooltip: l.editStaff,
                                    icon: const Icon(Icons.edit_outlined),
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
            ),
          ],
        ],
      ),
    );
  }
}

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
  late String _defaultLanguage = widget.info.defaultLanguage;
  late String _documentLanguage = widget.info.documentLanguage;
  bool _busy = false;
  bool _saved = false;
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
      _saved = false;
    });
    try {
      await widget.repository.updateBusiness(
        name: _name.text.trim(),
        defaultLanguage: _defaultLanguage,
        documentLanguage: _documentLanguage,
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
        TextField(
          key: const ValueKey('business-name'),
          controller: _name,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: l.businessName,
            errorText: fieldError(l, _error, 'name'),
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
        const SizedBox(height: 4),
        Text(
          '${l.timezoneLabel}: ${widget.info.timezone}',
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
          GradientButton(
            key: const ValueKey('business-save'),
            label: l.save,
            icon: Icons.check,
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
      child: DropdownButtonFormField<String>(
        key: fieldKey,
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: 'ru', child: Text(l.languageRussian)),
          DropdownMenuItem(value: 'tk', child: Text(l.languageTurkmen)),
        ],
        onChanged: enabled ? (v) => onChanged(v ?? value) : null,
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
              TextField(
                key: const ValueKey('location-name'),
                controller: _name,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l.locationName,
                  errorText: fieldError(l, _error, 'name'),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('location-kind'),
                initialValue: _kind,
                decoration: InputDecoration(labelText: l.locationKind),
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
                TextField(
                  key: const ValueKey('staff-username'),
                  controller: _username,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.username,
                    errorText: fieldError(l, _error, 'username'),
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('staff-email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l.emailLabel,
                    errorText: fieldError(l, _error, 'email'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('staff-full-name'),
                  controller: _fullName,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l.fullNameLabel),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('staff-language'),
                  initialValue: _language,
                  decoration: InputDecoration(labelText: l.language),
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
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                key: const ValueKey('staff-role'),
                initialValue: _role,
                decoration: InputDecoration(labelText: l.roleLabel),
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
                TextField(
                  key: const ValueKey('staff-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l.initialPasswordLabel,
                    helperText: l.initialPasswordHint,
                    helperMaxLines: 3,
                    errorText: fieldError(l, _error, 'password'),
                    errorMaxLines: 3,
                  ),
                ),
              ],
              if (_editing) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('staff-send-code'),
                  onPressed: _busy ? null : _sendCode,
                  icon: const Icon(Icons.mail_outline),
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
