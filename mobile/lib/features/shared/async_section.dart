import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

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
              const Icon(Icons.error_outline, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('retry-load'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
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
  const AsyncSection({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<AsyncSection<T>> createState() => AsyncSectionState<T>();
}

class AsyncSectionState<T> extends State<AsyncSection<T>> {
  late Future<T> _future = widget.load();

  void reload() {
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return ErrorPanel(error: snapshot.error!, onRetry: reload);
      }
      return widget.builder(context, snapshot.data as T);
    },
  );
}
