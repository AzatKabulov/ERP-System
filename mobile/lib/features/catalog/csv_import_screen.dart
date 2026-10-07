import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

const importColumns =
    'sku;name;unit;category;brand;price;currency;default_cost;warranty_months;warranty_terms;return_days;barcodes';

/// Add many products from a CSV file. The whole file is checked first and every problem is
/// listed by row; only a file without problems can be added, and then all of it is added at
/// once (never half of it). Importing never changes stock.
class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({super.key, required this.repository});

  final CatalogRepository repository;

  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  PickedFile? _file;
  ImportPreview? _preview;
  int? _created;
  bool _busy = false;
  ApiException? _error;

  Future<void> _choose() async {
    final file = await FilesScope.pickingOf(
      context,
    ).pickFile(extensions: const ['csv', 'txt']);
    if (file == null || !mounted) return;
    setState(() {
      _file = file;
      _preview = null;
      _created = null;
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.previewImport(file);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  Future<void> _apply() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.repository.applyImport(file);
      if (!mounted) return;
      setState(() {
        _created = created;
        _preview = null;
        _file = null;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  String _rowError(AppLocalizations l, ImportError e) => l.importErrorRow(
    e.row,
    e.field,
    fieldErrorText(l, FieldError(e.code, '')),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(l.importTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.importHelp),
                        const SizedBox(height: 8),
                        SelectableText(
                          importColumns,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GradientButton(
                      key: const ValueKey('import-choose'),
                      label: l.importChoose,
                      icon: Icons.upload_file,
                      onPressed: _busy ? null : _choose,
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_file != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l.importChosen(_file!.name),
                        key: const ValueKey('import-file'),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _errorText(l, _error!),
                        key: const ValueKey('import-error'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                    ..._rows(l, _error!.params['errors']),
                  ],
                  if (preview != null) ...[
                    const SizedBox(height: 16),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.importSummary(preview.rows, preview.valid),
                            key: const ValueKey('import-summary'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (preview.errorCount == 0 && preview.rows > 0)
                            Text(
                              l.importNoErrors,
                              key: const ValueKey('import-ok'),
                              style: const TextStyle(color: AppColors.success),
                            ),
                          if (preview.errors.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              l.importErrorsTitle(preview.errorCount),
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            for (final e in preview.errors.take(50))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _rowError(l, e),
                                  key: ValueKey(
                                    'import-row-${e.row}-${e.field}',
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            if (preview.errorCount > 50)
                              Text(
                                l.importErrorsMore,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GradientButton(
                        key: const ValueKey('import-apply'),
                        label: l.importApply,
                        icon: Icons.check,
                        onPressed: _busy || !preview.canApply ? null : _apply,
                      ),
                    ),
                  ],
                  if (_created != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        l.importDone(_created!),
                        key: const ValueKey('import-done'),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(AppLocalizations l, Object? errors) {
    if (errors is! List) return const [];
    return [
      for (final e in errors.take(50))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _rowError(
              l,
              ImportError.fromJson((e as Map).cast<String, dynamic>()),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
    ];
  }

  String _errorText(AppLocalizations l, ApiException e) => switch (e.code) {
    'import_too_large' => l.errorImportTooLarge,
    'invalid_header' => l.errorImportHeader,
    'import_invalid' => l.errorImportInvalid,
    _ => apiErrorText(l, e),
  };
}
