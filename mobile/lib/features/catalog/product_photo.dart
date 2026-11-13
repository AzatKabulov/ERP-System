import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/files/file_services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/motion.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

/// A bounded image placeholder during download/decoding, or a box icon for missing/failed photos.
/// Pictures come through the repository, which
/// shares concurrent downloads and retains recent pictures within its memory
/// budget. Evicted pictures are fetched again when needed. Small ones
/// (`full: false`) serve lists, large ones the product page.
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
    this.placeholderLabel,
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
  final String? placeholderLabel;

  Widget _tile(Widget? child) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(radius),
    ),
    child:
        child ??
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(),
              if (placeholderLabel != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    placeholderLabel!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
  );

  Widget _icon() =>
      AppIcon(AppIcons.box, size: iconSize, color: AppColors.blue);

  Widget _loading() => SkeletonRegion(
    // Lists may contain hundreds of photos; avoid a ticker for each thumbnail.
    animate: false,
    child: SkeletonBase(
      width: double.infinity,
      height: double.infinity,
      radius: radius,
    ),
  );

  Widget _image(Uint8List bytes, BuildContext context) => _tile(
    ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.memory(
        bytes,
        key: const ValueKey('product-photo-image'),
        fit: fit,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, synchronous) => AnimatedSwitcher(
          duration: AppMotion.of(context, const Duration(milliseconds: 180)),
          child: synchronous || frame != null ? child : _loading(),
        ),
        errorBuilder: (_, _, _) => Center(child: _icon()),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (product.photoVersion == null) {
      inner = _tile(null);
    } else if (repository.cachedPhoto(product, full: full) case final bytes?) {
      inner = _image(bytes, context);
    } else {
      inner = FutureBuilder<Uint8List?>(
        future: repository.photo(product, full: full),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done &&
              bytes == null) {
            return _loading();
          }
          return bytes == null ? _tile(null) : _image(bytes, context);
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

  Future<void> _view() => showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: AppColors.surface,
      child: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(dialog).height * .8,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const ValueKey('photo-viewer-close'),
                tooltip: strings(dialog).close,
                onPressed: () => Navigator.pop(dialog),
                icon: const AppIcon(AppIcons.close),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                key: const ValueKey('photo-viewer'),
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: ProductPhoto(
                    product: widget.product,
                    repository: widget.repository,
                    full: true,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
          Semantics(
            button: has,
            label: has ? l.productPhotoOpen : l.productPhotoNone,
            child: InkWell(
              key: const ValueKey('pd-photo-open'),
              onTap: has ? () => _view() : null,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ProductPhoto(
                    key: ValueKey('pd-photo-${widget.product.photoVersion}'),
                    product: widget.product,
                    repository: widget.repository,
                    full: true,
                    aspectRatio: 4 / 3,
                    fit: BoxFit.contain,
                    iconSize: 48,
                  ),
                ),
              ),
            ),
          ),
          if (has)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.productPhotoZoomHint,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          if (!has && widget.canEdit) ...[
            const SizedBox(height: 8),
            Text(
              l.productPhotoNone,
              key: const ValueKey('pd-photo-none'),
              style: TextStyle(color: AppColors.muted),
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (camera) ...[
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('pd-photo-take'),
                      onPressed: _busy ? null : () => _pick(camera: true),
                      icon: const AppIcon(AppIcons.camera, size: 18),
                      label: Text(
                        l.productPhotoTake,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('pd-photo-choose'),
                    onPressed: _busy ? null : () => _pick(camera: false),
                    icon: const AppIcon(AppIcons.image, size: 18),
                    label: Text(
                      has ? l.productPhotoChange : l.productPhotoChoose,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            if (has) const SizedBox(height: 8),
            if (has)
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  key: const ValueKey('pd-photo-remove'),
                  onPressed: _busy ? null : _remove,
                  icon: AppIcon(
                    AppIcons.trash,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  label: Text(
                    l.productPhotoRemove,
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('pd-photo-error'),
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
