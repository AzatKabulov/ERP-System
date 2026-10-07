import 'package:flutter/material.dart';

import '../demo/demo_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

AppLocalizations strings(BuildContext context) => AppLocalizations.of(context);

String money(int minor) {
  final absolute = minor.abs();
  final integer = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '\u00a0',
  );
  final decimal = (absolute % 100).toString().padLeft(2, '0');
  return '${minor < 0 ? '−' : ''}$integer,$decimal\u00a0TMT';
}

int? parseMinor(String input) {
  final normalized = input
      .trim()
      .replaceAll(' ', '')
      .replaceAll('\u00a0', '')
      .replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null || major > 999999999) return null;
  return major * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String locationLabel(AppLocalizations l, String id) => switch (id) {
  'warehouse' => l.warehouse,
  'branch' => l.branch,
  _ => l.store,
};

String categoryLabel(AppLocalizations l, ProductCategory category) =>
    switch (category) {
      ProductCategory.filters => l.filters,
      ProductCategory.brakes => l.brakes,
      ProductCategory.oils => l.oils,
      ProductCategory.electrical => l.electrical,
    };

IconData categoryIcon(ProductCategory category) => switch (category) {
  ProductCategory.filters => Icons.filter_alt_outlined,
  ProductCategory.brakes => Icons.album_outlined,
  ProductCategory.oils => Icons.water_drop_outlined,
  ProductCategory.electrical => Icons.bolt_outlined,
};

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: child,
  );
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: onPressed == null
          ? null
          : const LinearGradient(
              colors: [AppColors.blue, AppColors.gradientEnd],
            ),
      color: onPressed == null ? AppColors.line : null,
      borderRadius: BorderRadius.circular(12),
    ),
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.warning = false});
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: warning ? AppColors.warning : AppColors.success,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class ProductMark extends StatelessWidget {
  const ProductMark({super.key, required this.product, this.size = 48});
  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      categoryIcon(product.category),
      color: AppColors.blue,
      size: 24,
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
  });
  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 36, color: AppColors.muted),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.blue, size: 24),
        const SizedBox(height: 16),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minimumWidth = 220,
  });
  final List<Widget> children;
  final double minimumWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = ((constraints.maxWidth + 16) / (minimumWidth + 16))
          .floor()
          .clamp(1, 4);
      final width = (constraints.maxWidth - (count - 1) * 16) / count;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 8,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      ?action,
    ],
  );
}

/// Shows a short message. A newer message replaces the one still on screen instead of
/// waiting behind it, so what the user reads is always the latest outcome.
void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async {
  final l = strings(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.confirm),
            ),
          ],
        ),
      ) ??
      false;
}

/// Owns an input controller for the entire dialog route, including dismissal.
class DialogInput extends StatefulWidget {
  const DialogInput({super.key, this.initialText = '', required this.builder});
  final String initialText;
  final Widget Function(BuildContext, TextEditingController) builder;
  @override
  State<DialogInput> createState() => _DialogInputState();
}

class _DialogInputState extends State<DialogInput> {
  late final _controller = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
