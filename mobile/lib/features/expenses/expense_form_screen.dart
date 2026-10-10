import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'expenses_models.dart';
import 'expenses_repository.dart';

const _newCategoryValue = '__new__';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Record an expense, or change one: category, amount, day, place, a short description, and
/// optionally a photo of the receipt (taken now or chosen from the device). The photo is
/// stored on the server first; the expense then refers to it. Returns the saved expense.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.unsaved,
    this.existing,
  });

  final SessionController session;
  final ExpensesRepository repository;
  final UnsavedWork unsaved;
  final Expense? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final Future<List<ExpenseCategory>> _loaded = widget.repository
      .categories();
  List<ExpenseCategory> _categories = const [];
  late String? _categoryId = widget.existing?.categoryId;
  late String? _locationId =
      widget.existing?.locationId ??
      widget.session.location?.id ??
      widget.session.membership?.locations.firstOrNull?.id;
  late String _date = widget.existing?.spentOn ?? _day(DateTime.now());
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : toServerDecimal(widget.existing!.amountMinor, 2).replaceAll('.', ','),
  );
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late AttachmentRef? _attachment = widget.existing?.attachment;
  bool _dirty = false;
  bool _saving = false;
  bool _uploading = false;
  bool _submitted = false;
  ApiException? _error;

  @override
  void dispose() {
    widget.unsaved.mark(this, dirty: false);
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) {
      _dirty = true;
      widget.unsaved.mark(this, dirty: true);
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final parsed = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _date = _day(picked);
      _touch();
    }
  }

  Future<void> _addCategory() async {
    final l = strings(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => DialogInput(
        builder: (context, controller) => AlertDialog(
          title: Text(l.expenseNewCategoryTitle),
          content: TextField(
            key: const ValueKey('ef-new-category-name'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l.expenseCategoryName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('ef-new-category-save'),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final created = await widget.repository.createCategory(name);
      if (!mounted) return;
      _categories = [..._categories, created];
      _categoryId = created.id;
      _touch();
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, apiErrorText(strings(context), e));
    }
  }

  Future<void> _attach({required bool camera}) async {
    final picker = FilesScope.pickingOf(context);
    final file = camera
        ? await picker.pickPhoto(camera: true)
        : await picker.pickFile(
            extensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
          );
    if (file == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final stored = await widget.repository.upload(file);
      if (!mounted) return;
      _attachment = stored;
      _uploading = false;
      _touch();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e;
      });
    }
  }

  int? get _amountMinor {
    final minor = parseScaled(_amount.text, 2);
    return minor == null || minor <= 0 ? null : minor;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_categoryId == null || _locationId == null || _amountMinor == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = widget.repository;
      final saved = widget.existing == null
          ? await repo.createExpense(
              categoryId: _categoryId!,
              locationId: _locationId!,
              amountMinor: _amountMinor!,
              spentOn: _date,
              description: _description.text.trim(),
              attachmentId: _attachment?.id,
            )
          : await repo.updateExpense(
              widget.existing!.id,
              categoryId: _categoryId!,
              locationId: _locationId!,
              amountMinor: _amountMinor!,
              spentOn: _date,
              description: _description.text.trim(),
              attachmentId: _attachment?.id,
            );
      if (!mounted) return;
      _dirty = false;
      widget.unsaved.mark(this, dirty: false);
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final locations = widget.session.membership?.locations ?? const [];
    final picker = FilesScope.pickingOf(context);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          l.expenseAddButton,
          l.unsavedChangeConflict,
        );
        if (leave && context.mounted) {
          _dirty = false;
          widget.unsaved.mark(this, dirty: false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.expenseAddButton)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FutureBuilder<List<ExpenseCategory>>(
                future: _loaded,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ErrorPanel(
                      error: snapshot.error!,
                      onRetry: () => setState(() {}),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_categories.isEmpty) {
                    _categories = [...snapshot.data!];
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          // a category added on the spot must show in the box
                          key: ValueKey('ef-category-$_categoryId'),
                          child: DropdownButtonFormField<String>(
                            key: const ValueKey('ef-category'),
                            isExpanded: true,
                            initialValue:
                                _categories.any((c) => c.id == _categoryId)
                                ? _categoryId
                                : null,
                            decoration: InputDecoration(
                              labelText: l.expenseCategoryLabel,
                              errorText: _submitted && _categoryId == null
                                  ? l.fieldRequired
                                  : null,
                            ),
                            items: [
                              for (final c in _categories)
                                if (c.isActive || c.id == _categoryId)
                                  DropdownMenuItem<String>(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                              DropdownMenuItem<String>(
                                value: _newCategoryValue,
                                child: Text(l.expenseNewCategory),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (v == _newCategoryValue) {
                                      _addCategory();
                                    } else {
                                      _categoryId = v;
                                      _touch();
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: TextField(
                            key: const ValueKey('ef-amount'),
                            controller: _amount,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9 .,]'),
                              ),
                            ],
                            onChanged: (_) => _touch(),
                            decoration: InputDecoration(
                              labelText: l.expenseAmountLabel,
                              errorText: _submitted && _amountMinor == null
                                  ? l.fieldInvalid
                                  : fieldError(l, _error, 'amount'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l.expenseDateLabel(_date),
                              key: const ValueKey('ef-date-text'),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('ef-date'),
                              onPressed: _saving ? null : _pickDate,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(l.pickDate),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('ef-location'),
                          isExpanded: true,
                          initialValue:
                              locations.any((x) => x.id == _locationId)
                              ? _locationId
                              : null,
                          decoration: InputDecoration(
                            labelText: l.expenseLocationLabel,
                          ),
                          items: [
                            for (final x in locations)
                              DropdownMenuItem<String>(
                                value: x.id,
                                child: Text(x.name),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (v) {
                                  _locationId = v;
                                  _touch();
                                },
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: TextField(
                            key: const ValueKey('ef-description'),
                            controller: _description,
                            enabled: !_saving,
                            minLines: 1,
                            maxLines: 3,
                            onChanged: (_) => _touch(),
                            decoration: InputDecoration(
                              labelText: l.expenseDescriptionLabel,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionHeading(l.expenseReceipt),
                        const SizedBox(height: 8),
                        if (_attachment != null)
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Icon(Icons.attach_file, size: 18),
                              Text(
                                l.expenseReceiptAttached(_attachment!.name),
                                key: const ValueKey('ef-attached'),
                              ),
                              TextButton(
                                key: const ValueKey('ef-remove-receipt'),
                                onPressed: _saving
                                    ? null
                                    : () {
                                        _attachment = null;
                                        _touch();
                                      },
                                child: Text(l.expenseRemoveReceipt),
                              ),
                            ],
                          )
                        else
                          Text(
                            l.expenseReceiptNone,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (picker.hasCamera)
                              OutlinedButton.icon(
                                key: const ValueKey('ef-take-photo'),
                                onPressed: _saving || _uploading
                                    ? null
                                    : () => _attach(camera: true),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(l.expenseTakePhoto),
                              ),
                            OutlinedButton.icon(
                              key: const ValueKey('ef-choose-file'),
                              onPressed: _saving || _uploading
                                  ? null
                                  : () => _attach(camera: false),
                              icon: const Icon(Icons.folder_open_outlined),
                              label: Text(l.expenseChoosePhoto),
                            ),
                            if (_uploading)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              apiErrorText(l, _error!),
                              key: const ValueKey('ef-error'),
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        GradientButton(
                          key: const ValueKey('ef-save'),
                          label: l.save,
                          icon: Icons.check,
                          onPressed: _saving || _uploading ? null : _save,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
