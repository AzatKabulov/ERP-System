import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

const _addNew = '__add_new__';

/// A drop-down of categories or brands with a "add new" entry at the end.
class NamedRefPicker extends StatelessWidget {
  const NamedRefPicker({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.onAddNew,
    this.enabled = true,
    this.errorText,
    this.allowNone = true,
  });

  final String label;
  final List<NamedRef> items;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Creates a new entry and returns it (or null if cancelled).
  final Future<NamedRef?> Function() onAddNew;
  final bool enabled;
  final String? errorText;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: items.any((i) => i.id == value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        errorMaxLines: 3,
      ),
      items: [
        if (allowNone) DropdownMenuItem(value: null, child: Text(l.noneOption)),
        for (final item in items)
          DropdownMenuItem(
            value: item.id,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
        DropdownMenuItem(
          value: _addNew,
          child: Row(
            children: [
              const Icon(Icons.add, size: 18, color: AppColors.blue),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l.addNewOption,
                  style: const TextStyle(color: AppColors.blue),
                ),
              ),
            ],
          ),
        ),
      ],
      onChanged: !enabled
          ? null
          : (id) async {
              if (id != _addNew) return onChanged(id);
              final created = await onAddNew();
              if (created != null) onChanged(created.id);
            },
    );
  }
}

/// Asks for a name and creates a category or brand. Returns the new entry.
Future<NamedRef?> showCreateNamedDialog(
  BuildContext context, {
  required String title,
  required Future<NamedRef> Function(String name) create,
}) => showDialog<NamedRef>(
  context: context,
  builder: (_) => _NameDialog<NamedRef>(
    title: title,
    submit: (name, symbol, decimals) => create(name),
  ),
);

/// Asks for name, symbol and decimals and creates a unit of measure.
Future<UnitRef?> showCreateUnitDialog(
  BuildContext context,
  CatalogRepository repository,
) => showDialog<UnitRef>(
  context: context,
  builder: (_) => _NameDialog<UnitRef>(
    title: strings(context).addUnit,
    withUnitFields: true,
    submit: (name, symbol, decimals) => repository.createUnit(
      name: name,
      symbol: symbol,
      decimalPlaces: decimals,
    ),
  ),
);

class _NameDialog<T> extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.submit,
    this.withUnitFields = false,
  });
  final String title;
  final bool withUnitFields;
  final Future<T> Function(String name, String symbol, int decimals) submit;

  @override
  State<_NameDialog<T>> createState() => _NameDialogState<T>();
}

class _NameDialogState<T> extends State<_NameDialog<T>> {
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  int _decimals = 0;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.submit(
        _name.text.trim(),
        _symbol.text.trim(),
        _decimals,
      );
      if (mounted) Navigator.of(context).pop(created);
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
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('reference-name'),
                controller: _name,
                enabled: !_busy,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.businessName,
                  errorText: fieldError(l, _error, 'name'),
                ),
              ),
              if (widget.withUnitFields) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('reference-symbol'),
                  controller: _symbol,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: l.unitSymbol,
                    errorText: fieldError(l, _error, 'symbol'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('reference-decimals'),
                  initialValue: _decimals,
                  decoration: InputDecoration(
                    labelText: l.unitDecimals,
                    errorText: fieldError(l, _error, 'decimal_places'),
                  ),
                  items: [
                    for (var i = 0; i <= 3; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _decimals = v ?? 0),
                ),
              ],
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('reference-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
