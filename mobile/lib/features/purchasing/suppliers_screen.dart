import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

/// Create or edit a supplier. Returns the saved supplier, or null if cancelled.
Future<Supplier?> showSupplierDialog(
  BuildContext context,
  PurchasingRepository repository, {
  Supplier? existing,
  bool canArchive = false,
}) => showDialog<Supplier>(
  context: context,
  builder: (_) => _SupplierDialog(
    repository: repository,
    existing: existing,
    canArchive: canArchive,
  ),
);

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({
    required this.repository,
    required this.canArchive,
    this.existing,
  });
  final PurchasingRepository repository;
  final Supplier? existing;
  final bool canArchive;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _contact = TextEditingController(
    text: widget.existing?.contactName ?? '',
  );
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  bool _busy = false;
  bool _missingName = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<Supplier> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await action();
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _missingName = true);
      return;
    }
    final fields = {
      'name': _name.text.trim(),
      'contact_name': _contact.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
    };
    _run(
      () => widget.existing == null
          ? widget.repository.createSupplier(fields)
          : widget.repository.updateSupplier(widget.existing!.id, fields),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final existing = widget.existing;
    Widget field(
      String key,
      TextEditingController c,
      String label, {
      int lines = 1,
      String? error,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey(key),
        controller: c,
        enabled: !_busy,
        maxLines: lines,
        minLines: 1,
        decoration: InputDecoration(labelText: label, errorText: error),
      ),
    );
    return AlertDialog(
      title: Text(existing == null ? l.addSupplier : l.editSupplier),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(
                'supplier-name',
                _name,
                l.supplierName,
                error: _missingName && _name.text.trim().isEmpty
                    ? l.fieldRequired
                    : fieldError(l, _error, 'name'),
              ),
              field('supplier-contact', _contact, l.contactName),
              field('supplier-phone', _phone, l.phoneLabel),
              field('supplier-email', _email, l.emailLabel),
              field('supplier-address', _address, l.addressLabel),
              field('supplier-notes', _notes, l.notesLabel, lines: 3),
              if (_error != null && _error!.fields.isEmpty)
                Text(
                  apiErrorText(l, _error!),
                  style: const TextStyle(color: AppColors.danger),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null && widget.canArchive)
          TextButton(
            key: const ValueKey('supplier-toggle'),
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.repository.updateSupplier(existing.id, {
                      'is_active': !existing.isActive,
                    }),
                  ),
            child: Text(existing.isActive ? l.deactivate : l.activate),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('supplier-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// The supplier list with add and edit for those who may.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final PurchasingRepository repository;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _list = GlobalKey<AsyncSectionState<SupplierPage>>();
  bool _archived = false;

  bool get _canManage => widget.session.can('supplier.manage');

  Future<void> _edit([Supplier? supplier]) async {
    final saved = await showSupplierDialog(
      context,
      widget.repository,
      existing: supplier,
      canArchive: _canManage,
    );
    if (saved != null && mounted) {
      showFeedback(context, strings(context).supplierSaved);
      _list.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.suppliersTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_canManage)
                      GradientButton(
                        key: const ValueKey('supplier-add'),
                        label: l.addSupplier,
                        icon: Icons.add,
                        onPressed: () => _edit(),
                      ),
                    FilterChip(
                      key: const ValueKey('supplier-archived-toggle'),
                      label: Text(l.showArchived),
                      selected: _archived,
                      onSelected: (v) {
                        setState(() => _archived = v);
                        _list.currentState?.reload();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AsyncSection<SupplierPage>(
                  key: _list,
                  load: () => widget.repository.suppliers(archived: _archived),
                  builder: (context, page) {
                    if (page.items.isEmpty) {
                      return SurfaceCard(
                        child: EmptyState(
                          key: const ValueKey('suppliers-empty'),
                          title: l.noSuppliers,
                          subtitle: l.noSuppliersHint,
                          icon: Icons.local_shipping_outlined,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final s in page.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: ValueKey('supplier-${s.name}'),
                                borderRadius: BorderRadius.circular(16),
                                onTap: _canManage ? () => _edit(s) : null,
                                child: SurfaceCard(
                                  padding: 14,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if ([
                                              s.contactName,
                                              s.phone,
                                            ].any((t) => t.isNotEmpty))
                                              Text(
                                                [s.contactName, s.phone]
                                                    .where((t) => t.isNotEmpty)
                                                    .join(' · '),
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 13,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (!s.isActive)
                                        StatusPill(
                                          label: l.archivedLabel,
                                          warning: true,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
