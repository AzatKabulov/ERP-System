import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../shared/async_section.dart';

String _rateText(String serverRate) {
  final scaled = parseServerDecimal(serverRate, 6);
  return scaled == null ? serverRate : formatRate(scaled);
}

/// The USD -> TMT rate: shows the current one and its history, and lets an owner or
/// manager enter a new one. A rate is never edited; a new entry supersedes the old,
/// and a sale keeps the rate it was made with.
class ExchangeRateSection extends StatefulWidget {
  const ExchangeRateSection({
    super.key,
    required this.repository,
    required this.canManage,
  });

  final CatalogRepository repository;
  final bool canManage;

  @override
  State<ExchangeRateSection> createState() => _ExchangeRateSectionState();
}

class _ExchangeRateSectionState extends State<ExchangeRateSection> {
  final _section = GlobalKey<AsyncSectionState<List<ExchangeRateEntry>>>();
  final _input = TextEditingController();
  bool _busy = false;
  ApiException? _error;
  bool _invalid = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final scaled = parseScaled(_input.text, 6);
    if (scaled == null || scaled <= 0) {
      setState(() {
        _invalid = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
      _error = null;
    });
    try {
      await widget.repository.setExchangeRate(toServerDecimal(scaled, 6));
      _input.clear();
      _section.currentState?.reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final fieldText = _invalid ? l.fieldInvalid : fieldError(l, _error, 'rate');
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l.exchangeRateTitle),
          const SizedBox(height: 12),
          AsyncSection<List<ExchangeRateEntry>>(
            key: _section,
            load: () => widget.repository.exchangeRates(limit: 6),
            builder: (context, rates) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rates.isEmpty)
                  Text(
                    l.noRateYet,
                    key: const ValueKey('rate-none'),
                    style: const TextStyle(color: AppColors.warning),
                  )
                else
                  Text(
                    l.currentRate(_rateText(rates.first.rate)),
                    key: const ValueKey('rate-current'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                if (rates.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.rateHistory,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  for (final entry in rates.skip(1))
                    Text(
                      l.rateHistoryEntry(
                        _rateText(entry.rate),
                        entry.setBy,
                        formatStamp(entry.createdAt),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ],
            ),
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    key: const ValueKey('rate-input'),
                    controller: _input,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: l.newRateLabel,
                      errorText: fieldText,
                      errorMaxLines: 3,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GradientButton(
                    key: const ValueKey('rate-save'),
                    label: l.setRate,
                    icon: Icons.check,
                    onPressed: _busy ? null : _save,
                  ),
                ),
              ],
            ),
            if (_error != null && _error!.fields.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                apiErrorText(l, _error!),
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
