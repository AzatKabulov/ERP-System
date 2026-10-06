import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/money/decimal_math.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../workspace/unsaved_work.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';
import 'product_form_screen.dart';

/// One product, read-only, with edit and archive for those who may. Closes with
/// `true` when something was changed so the list can refresh.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.repository,
    required this.session,
    required this.unsaved,
  });

  final Product product;
  final CatalogRepository repository;
  final SessionController session;
  final UnsavedWork unsaved;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _product = widget.product;
  bool _changed = false;
  bool _busy = false;

  bool get _canManage => widget.session.can('catalog.manage');

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Product>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          repository: widget.repository,
          session: widget.session,
          unsaved: widget.unsaved,
          existing: _product,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _product = saved;
        _changed = true;
      });
      showFeedback(context, strings(context).productSaved);
    }
  }

  Future<void> _toggleActive() async {
    if (_busy) return;
    final l = strings(context);
    if (_product.isActive &&
        !await confirmAction(context, l.archiveProduct, l.archiveConfirm)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.setActive(
        _product.id,
        !_product.isActive,
      );
      if (mounted) {
        setState(() {
          _product = updated;
          _changed = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) showFeedback(context, apiErrorText(strings(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final p = _product;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.productCardTitle),
          actions: [
            if (_canManage)
              IconButton(
                key: const ValueKey('pd-edit'),
                tooltip: l.editProduct,
                icon: const Icon(Icons.edit_outlined),
                onPressed: _busy ? null : _edit,
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                p.name,
                                key: const ValueKey('pd-name'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (!p.isActive)
                                StatusPill(
                                  label: l.archivedLabel,
                                  warning: true,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              p.sku,
                              ?p.brand?.name,
                              ?p.category?.name,
                            ].join(' · '),
                            key: const ValueKey('pd-meta'),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            formatMoney(p.priceMinor, p.priceCurrency),
                            key: const ValueKey('pd-price'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (p.priceCurrency != 'TMT') ...[
                            const SizedBox(height: 4),
                            if (p.priceTmtMinor != null)
                              Text(
                                l.priceInTmt(
                                  formatMoney(p.priceTmtMinor!, 'TMT'),
                                ),
                                key: const ValueKey('pd-price-tmt'),
                                style: const TextStyle(color: AppColors.muted),
                              )
                            else
                              Text(
                                l.rateMissingNote,
                                key: const ValueKey('pd-rate-missing'),
                                style: const TextStyle(
                                  color: AppColors.warning,
                                ),
                              ),
                          ],
                          if (p.defaultCostMinor != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '${l.defaultCostLabel}: ${formatMoney(p.defaultCostMinor!, 'TMT')}',
                              key: const ValueKey('pd-cost'),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            '${l.unitLabel}: ${p.unit.name} (${p.unit.symbol})',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeading(l.barcodesLabel),
                          const SizedBox(height: 8),
                          if (p.barcodes.isEmpty)
                            const Text('—')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final code in p.barcodes)
                                  Chip(
                                    label: Text(
                                      code,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeading(l.warrantyTermsLabel),
                          const SizedBox(height: 8),
                          Text(
                            p.warrantyMonths == 0
                                ? '—'
                                : l.warrantyMonthsValue(p.warrantyMonths),
                            key: const ValueKey('pd-warranty'),
                          ),
                          if (p.warrantyTerms.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              p.warrantyTerms,
                              style: const TextStyle(height: 1.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_canManage) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: ValueKey(
                            p.isActive ? 'pd-archive' : 'pd-restore',
                          ),
                          onPressed: _busy ? null : _toggleActive,
                          icon: Icon(
                            p.isActive
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined,
                          ),
                          label: Text(
                            p.isActive ? l.archiveProduct : l.restoreProduct,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
