import '../shared/loading_skeletons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// What the person chose in the customer picker. [customer] null means "no customer";
/// closing the dialog without choosing returns null (nothing changes).
class CustomerChoice {
  const CustomerChoice(this.customer);
  final Customer? customer;
}

Future<CustomerChoice?> showCustomerPicker(
  BuildContext context,
  SalesRepository repository, {
  bool canCreate = true,
}) => showDialog<CustomerChoice>(
  context: context,
  builder: (_) =>
      _CustomerPickerDialog(repository: repository, canCreate: canCreate),
);

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    required this.repository,
    required this.canCreate,
  });
  final bool canCreate;
  final SalesRepository repository;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _surname = TextEditingController();
  Timer? _debounce;
  List<Customer> _items = const [];
  bool _loading = true;
  Object? _error;
  bool _creating = false;
  bool _busy = false;
  bool _missingName = false;
  ApiException? _createError;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    _surname.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.customers(query: _search.text);
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _missingName = true);
      return;
    }
    setState(() {
      _busy = true;
      _createError = null;
    });
    try {
      final created = await widget.repository.createCustomer(
        [
          _name.text.trim(),
          _surname.text.trim(),
        ].where((s) => s.isNotEmpty).join(' '),
        _phone.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(CustomerChoice(created));
    } on ApiException catch (e) {
      if (mounted) setState(() => _createError = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _creating ? l.customerNew : l.customerChoose,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('customer-close'),
                      tooltip: l.close,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const AppIcon(AppIcons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_creating)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l.customerContactHint,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 16),
                          LabeledField(
                            label: l.customerFirstName,
                            child: TextField(
                              key: const ValueKey('customer-name'),
                              controller: _name,
                              enabled: !_busy,
                              autofocus: true,
                              maxLength: 100,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.givenName],
                              decoration: InputDecoration(
                                errorText:
                                    _missingName && _name.text.trim().isEmpty
                                    ? l.fieldRequired
                                    : fieldError(l, _createError, 'name'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          LabeledField(
                            label: l.customerSurname,
                            child: TextField(
                              key: const ValueKey('customer-surname'),
                              controller: _surname,
                              enabled: !_busy,
                              maxLength: 99,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.familyName],
                            ),
                          ),
                          const SizedBox(height: 12),
                          LabeledField(
                            label: l.phoneLabel,
                            child: TextField(
                              key: const ValueKey('customer-phone'),
                              controller: _phone,
                              enabled: !_busy,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              maxLength: 60,
                              decoration: InputDecoration(
                                errorText: fieldError(l, _createError, 'phone'),
                              ),
                            ),
                          ),
                          if (_createError != null &&
                              _createError!.fields.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                apiErrorText(l, _createError!),
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _creating = false),
                                child: Text(l.cancel),
                              ),
                              FilledButton(
                                key: const ValueKey('customer-save'),
                                onPressed: _busy ? null : _create,
                                child: Text(l.save),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_creating) ...[
                  LabeledField(
                    label: l.customerSearchLabel,
                    child: TextField(
                      key: const ValueKey('customer-search'),
                      controller: _search,
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          _run,
                        );
                      },
                      decoration: InputDecoration(
                        prefixIcon: const AppIcon(AppIcons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('customer-none'),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(const CustomerChoice(null)),
                        icon: const AppIcon(AppIcons.personOff),
                        label: Text(l.customerNone),
                      ),
                      if (widget.canCreate)
                        TextButton.icon(
                          key: const ValueKey('customer-new'),
                          onPressed: () => setState(() => _creating = true),
                          icon: const AppIcon(AppIcons.personAdd),
                          label: Text(l.customerNew),
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  Flexible(child: _results(context)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final l = strings(context);
    if (_error != null) return ErrorPanel(error: _error!, onRetry: _run);
    if (_loading && _items.isEmpty) {
      return const RecordListSkeleton(inCard: false, rowHeight: 72);
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l.customersEmpty, style: TextStyle(color: AppColors.muted)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final c = _items[index];
        return ListTile(
          key: ValueKey('customer-${c.name}'),
          title: Text(c.name),
          subtitle: c.phone.isEmpty ? null : Text(c.phone),
          onTap: () => Navigator.of(context).pop(CustomerChoice(c)),
        );
      },
    );
  }
}
