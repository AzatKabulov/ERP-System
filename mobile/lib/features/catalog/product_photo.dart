import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// The picture of a product, or the plain tinted tile with an icon while there is none (or while
/// it is still being downloaded, or if it cannot be). Pictures come through the repository, which
/// keeps each one in memory, so a gallery of thirty products asks the server thirty times at most
/// and a repeat visit asks nobody. Small ones (`full: false`) serve lists, large ones the
/// product page.
class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    super.key,
    required this.product,
    required this.repository,
    this.full = false,
    this.width,
    this.height,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.radius = 12,
  });

  final Product product;
  final CatalogRepository repository;
  final bool full;
  final double? width;
  final double? height;

  /// Width over height, for a picture that takes the width it is given.
  final double? aspectRatio;
  final BoxFit fit;
  final double iconSize;
  final double radius;

  Widget _tile(Widget? child) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child ?? Center(child: _icon()),
  );

  Widget _icon() =>
      AppIcon(AppIcons.box, size: iconSize, color: AppColors.neutral);

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (product.photoVersion == null) {
      inner = _tile(null);
    } else {
      inner = FutureBuilder<Uint8List?>(
        future: repository.photo(product, full: full),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return _tile(null);
          return _tile(
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Image.memory(
                bytes,
                key: const ValueKey('product-photo-image'),
                fit: fit,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Center(child: _icon()),
              ),
            ),
          );
        },
      );
    }
    final sized = aspectRatio == null
        ? SizedBox(width: width, height: height, child: inner)
        : AspectRatio(aspectRatio: aspectRatio!, child: inner);
    return sized;
  }
}

/// On the product page: the picture and, for people who may add one, the buttons to take one with
/// the camera, choose one, replace it or remove it. The server makes the picture small and
/// removes what the camera wrote into it; here a photo is only picked and sent.
class ProductPhotoSection extends StatefulWidget {
  const ProductPhotoSection({
    super.key,
    required this.product,
    required this.repository,
    required this.canEdit,
    required this.onChanged,
  });

  final Product product;
  final CatalogRepository repository;
  final bool canEdit;

  /// Called with the product as the server now has it, after a picture was set or removed.
  final ValueChanged<Product> onChanged;

  @override
  State<ProductPhotoSection> createState() => _ProductPhotoSectionState();
}

class _ProductPhotoSectionState extends State<ProductPhotoSection> {
  bool _busy = false;
  String? _error;

  Future<void> _pick({required bool camera}) async {
    if (_busy) return;
    final l = strings(context);
    final picking = FilesScope.pickingOf(context);
    PickedFile? file;
    try {
      file = await picking.pickPhoto(camera: camera);
    } catch (_) {
      if (mounted) setState(() => _error = l.productPhotoPickFailed);
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.uploadPhoto(
        widget.product.id,
        file,
      );
      if (!mounted) return;
      widget.onChanged(updated);
      showFeedback(context, l.productPhotoSaved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final l = strings(context);
    if (!await confirmAction(
      context,
      l.productPhotoRemove,
      l.productPhotoRemoveConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.removePhoto(widget.product.id);
      if (!mounted) return;
      widget.onChanged(updated);
      showFeedback(context, l.productPhotoRemoved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = apiErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final has = widget.product.photoVersion != null;
    final camera = FilesScope.pickingOf(context).hasCamera;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(l.productPhotoTitle),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ProductPhoto(
                key: ValueKey('pd-photo-${widget.product.photoVersion}'),
                product: widget.product,
                repository: widget.repository,
                full: true,
                aspectRatio: 4 / 3,
                fit: BoxFit.contain,
                iconSize: 56,
              ),
            ),
          ),
          if (!has && widget.canEdit) ...[
            const SizedBox(height: 8),
            Text(
              l.productPhotoNone,
              key: const ValueKey('pd-photo-none'),
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (camera)
                  FilledButton.icon(
                    key: const ValueKey('pd-photo-take'),
                    onPressed: _busy ? null : () => _pick(camera: true),
                    icon: const AppIcon(AppIcons.camera),
                    label: Text(l.productPhotoTake),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('pd-photo-choose'),
                  onPressed: _busy ? null : () => _pick(camera: false),
                  icon: const AppIcon(AppIcons.image),
                  label: Text(
                    has ? l.productPhotoChange : l.productPhotoChoose,
                  ),
                ),
                if (has)
                  TextButton.icon(
                    key: const ValueKey('pd-photo-remove'),
                    onPressed: _busy ? null : _remove,
                    icon: const AppIcon(AppIcons.trash),
                    label: Text(l.productPhotoRemove),
                  ),
                if (_busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('pd-photo-error'),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
