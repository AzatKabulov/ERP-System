import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// A failed load: says what happened in the interface language and offers a retry.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final message = error is ApiException
        ? apiErrorText(l, error as ApiException)
        : l.loadFailed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.info, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('retry-load'),
            onPressed: onRetry,
            icon: const AppIcon(AppIcons.retry),
            label: Text(l.retry),
          ),
        ],
      ),
    );
  }
}

/// Loads data with explicit loading, error (with retry) and loaded states.
/// Call [AsyncSectionState.reload] through a [GlobalKey] to refresh after a change.
class AsyncSection<T> extends StatefulWidget {
  const AsyncSection({
    super.key,
    required this.load,
    required this.builder,
    required this.loadingBuilder,
    this.initialData,
  });
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final WidgetBuilder loadingBuilder;
  final T? initialData;

  @override
  State<AsyncSection<T>> createState() => AsyncSectionState<T>();
}

class AsyncSectionState<T> extends State<AsyncSection<T>> {
  late Future<T> _future = _read();
  late T? _data = widget.initialData;
  late bool _hasData = widget.initialData != null;
  int _generation = 0;

  Future<T> _read() async {
    final generation = ++_generation;
    final data = await widget.load();
    if (mounted && generation == _generation) {
      _data = data;
      _hasData = true;
    }
    return data;
  }

  void reload() {
    setState(() {
      _future = _read();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      final waiting = snapshot.connectionState != ConnectionState.done;
      if (!_hasData && waiting) return widget.loadingBuilder(context);
      if (!_hasData && snapshot.hasError) {
        return ErrorPanel(error: snapshot.error!, onRetry: reload);
      }
      // Keep the same subtree during refresh, including focused/edited forms.
      // A failed refresh retains the last successful result and offers retry.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!waiting && snapshot.hasError)
            ErrorPanel(error: snapshot.error!, onRetry: reload),
          KeyedSubtree(
            key: const ValueKey('async-section-content'),
            child: Stack(
              children: [
                widget.builder(context, _data as T),
                if (waiting)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SkeletonRegion(child: SkeletonBase(height: 3)),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
