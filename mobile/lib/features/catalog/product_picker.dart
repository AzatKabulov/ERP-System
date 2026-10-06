import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scanning/barcode_input.dart';
import '../shared/async_section.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// Asks which product a line is for: type a name, SKU or barcode, or scan the code.
/// A scan only fills the search box; the person still taps the product to choose it.
Future<Product?> showProductPicker(
  BuildContext context,
  CatalogRepository repository,
) => showDialog<Product>(
  context: context,
  builder: (_) => _ProductPickerDialog(repository: repository),
);

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.repository});
  final CatalogRepository repository;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Product> _items = const [];
  bool _loading = true;
  Object? _error;
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
    super.dispose();
  }

  Future<void> _run() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.products(
        query: _search.text,
        limit: 20,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = page.items;
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

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.pickProductTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('picker-close'),
                    tooltip: l.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BarcodeInput(
                fieldKey: const ValueKey('picker-search'),
                controller: _search,
                label: l.searchProducts,
                onChanged: _typed,
                onSubmitted: (_) => _run(),
                onScanned: (_) {
                  _debounce?.cancel();
                  _run();
                },
              ),
              const SizedBox(height: 12),
              Flexible(child: _results(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final l = strings(context);
    if (_error != null) return ErrorPanel(error: _error!, onRetry: _run);
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_items.isEmpty) {
      return EmptyState(title: l.noResults, subtitle: l.noResultsHint);
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final p = _items[index];
        return ListTile(
          key: ValueKey('picker-${p.sku}'),
          title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [p.sku, ?p.brand?.name].join(' · '),
            style: const TextStyle(color: AppColors.muted),
          ),
          trailing: Text(p.unit.symbol),
          onTap: () => Navigator.of(context).pop(p),
        );
      },
    );
  }
}
