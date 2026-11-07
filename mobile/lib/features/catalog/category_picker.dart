import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// What the person chose in [showCategoryPicker]. [category] is null for "all categories" (a
/// filter) or "no category" (a form). Closing the dialog without choosing returns null instead.
class CategoryPick {
  const CategoryPick(this.category);
  final NamedRef? category;
}

/// Opens the category list: search, tap to choose, and **create a new category right here**
/// (one tap, no trip to a settings page). Used wherever a category is chosen: the product
/// filter, the product form and the receiving form.
///
/// [allLabel] adds a first row that clears the choice ("All categories" in a filter, "No
/// category" in a form). A category typed in the search box that does not exist yet is offered
/// as "Create «name»"; if somebody created the same name a moment ago, that one is used.
Future<CategoryPick?> showCategoryPicker(
  BuildContext context, {
  required CatalogRepository repository,
  String? selectedId,
  String? allLabel,
  bool canCreate = true,
}) => showDialog<CategoryPick>(
  context: context,
  builder: (_) => _CategoryPickerDialog(
    repository: repository,
    selectedId: selectedId,
    allLabel: allLabel,
    canCreate: canCreate,
  ),
);

class _CategoryPickerDialog extends StatefulWidget {
  const _CategoryPickerDialog({
    required this.repository,
    required this.selectedId,
    required this.allLabel,
    required this.canCreate,
  });
  final CatalogRepository repository;
  final String? selectedId;
  final String? allLabel;
  final bool canCreate;

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final _search = TextEditingController();
  List<NamedRef> _items = const [];
  bool _loading = true;
  bool _creating = false;
  Object? _loadError;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await widget.repository.categories();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  String get _query => _search.text.trim();

  List<NamedRef> get _shown {
    final q = _query.toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  bool get _canOfferCreate =>
      widget.canCreate &&
      _query.isNotEmpty &&
      !_items.any((c) => c.name.toLowerCase() == _query.toLowerCase());

  Future<void> _create() async {
    final name = _query;
    if (name.isEmpty || _creating) return;
    final l = strings(context);
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      final category = await widget.repository.resolveReference(
        name,
        brand: false,
      );
      if (!mounted) return;
      Navigator.of(context).pop(CategoryPick(category));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _createError = apiErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final shown = _shown;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.categoryPickerTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const AppIcon(AppIcons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                label: l.categorySearchHint,
                child: TextField(
                  key: const ValueKey('category-search'),
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() => _createError = null),
                  onSubmitted: (_) {
                    if (_canOfferCreate) _create();
                  },
                  decoration: InputDecoration(
                    hintText: l.categorySearchHint,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: AppIcon(AppIcons.search, size: 20),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 48),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _loadError != null
                    ? ErrorPanel(error: _loadError!, onRetry: _load)
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          if (widget.allLabel != null && _query.isEmpty)
                            _Row(
                              key: const ValueKey('category-all'),
                              label: widget.allLabel!,
                              selected: widget.selectedId == null,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(const CategoryPick(null)),
                            ),
                          for (final c in shown)
                            _Row(
                              key: ValueKey('category-${c.name}'),
                              label: c.name,
                              selected: c.id == widget.selectedId,
                              onTap: () =>
                                  Navigator.of(context).pop(CategoryPick(c)),
                            ),
                          if (shown.isEmpty && !_canOfferCreate)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l.categoryNoMatch,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                        ],
                      ),
              ),
              if (_createError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _createError!,
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              if (widget.canCreate && !_loading && _loadError == null) ...[
                const Divider(height: 24),
                OutlinedButton.icon(
                  key: const ValueKey('category-create'),
                  onPressed: _canOfferCreate && !_creating ? _create : null,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.plus, size: 20),
                  label: Text(
                    _canOfferCreate
                        ? l.categoryCreateNamed(_query)
                        : l.categoryAdd,
                  ),
                ),
                if (!_canOfferCreate && _query.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l.categoryNewHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.tint : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.blue : AppColors.ink,
                ),
              ),
            ),
            if (selected)
              AppIcon(AppIcons.check, size: 18, color: AppColors.blue),
          ],
        ),
      ),
    ),
  );
}
