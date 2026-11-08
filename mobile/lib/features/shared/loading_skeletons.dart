import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Use the real subtitle's inherited font metrics, including text scaling. This
/// keeps a delayed result count from moving the toolbar below PageHead.
class SubtitleLoadingSkeleton extends StatelessWidget {
  const SubtitleLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 112,
      child: Stack(
        children: [
          const Text(' ', style: TextStyle(fontSize: 14)),
          const Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SkeletonBase(width: 112, height: 14, radius: 4),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared document-list geometry, also used by retained compatibility routes.
class RecordListSkeleton extends StatelessWidget {
  const RecordListSkeleton({
    super.key,
    this.rows = 4,
    this.avatar = false,
    this.inCard = true,
    this.rowHeight = 88,
  });
  final int rows;
  final bool avatar;
  final bool inCard;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => SkeletonList(
    rows: rows,
    avatar: avatar,
    inCard: inCard,
    rowHeight: rowHeight,
  );
}

class CatalogLoadingSkeleton extends StatelessWidget {
  const CatalogLoadingSkeleton({
    super.key,
    required this.gallery,
    required this.compact,
    this.withStock = false,
  });
  final bool gallery;
  final bool compact;
  final bool withStock;

  @override
  Widget build(BuildContext context) {
    if (!gallery) {
      if (compact) {
        return const SkeletonList(avatar: true, rowHeight: 104);
      }
      return SkeletonTable(
        rowHeight: 64,
        columns: [
          60,
          128,
          53,
          53,
          if (withStock) ...[53, 53],
        ],
      );
    }
    return SkeletonRegion(
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = ((box.maxWidth + 16) / 186).floor().clamp(2, 5);
          return Column(
            children: [
              for (var row = 0; row < 2; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var col = 0; col < columns; col++) ...[
                        if (col > 0) const SizedBox(width: 16),
                        Expanded(
                          child: SkeletonCard(
                            image: true,
                            padding: 12,
                            product: true,
                            stock: withStock,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class StockLoadingSkeleton extends StatelessWidget {
  const StockLoadingSkeleton({
    super.key,
    required this.compact,
    required this.withValue,
  });
  final bool compact;
  final bool withValue;
  @override
  Widget build(BuildContext context) =>
      SkeletonTable(compact: compact, columns: [4, 2, 3, 2, if (withValue) 2]);
}

class FormLoadingSkeleton extends StatelessWidget {
  const FormLoadingSkeleton({
    super.key,
    this.fields = 6,
    this.maxWidth = 720,
    this.columns = 1,
    this.padding = 20,
    this.actions = true,
  });
  final int fields;
  final double maxWidth;
  final int columns;
  final double padding;
  final bool actions;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    child: SkeletonForm(
      fields: fields,
      columns: columns,
      padding: padding,
      maxWidth: maxWidth,
      actions: actions,
    ),
  );
}

/// Matches the product editor's 320px wrapping reference controls and textarea.
class ProductFormLoadingSkeleton extends StatelessWidget {
  const ProductFormLoadingSkeleton({super.key, required this.canSeeCost});
  final bool canSeeCost;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SkeletonRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SkeletonForm(fields: 2, actions: false),
                const Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 320,
                      child: SkeletonForm(fields: 1, actions: false),
                    ),
                    SizedBox(
                      width: 320,
                      child: SkeletonForm(fields: 1, actions: false),
                    ),
                    SizedBox(
                      width: 320,
                      child: SkeletonForm(fields: 1, actions: false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: SkeletonForm(fields: 1, actions: false),
                    ),
                    SkeletonButton(width: 140),
                  ],
                ),
                if (canSeeCost)
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      width: 320,
                      child: SkeletonForm(fields: 1, actions: false),
                    ),
                  ),
                const SizedBox(height: 24),
                const SkeletonForm(fields: 1, actions: false),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SkeletonButton(),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 260,
                    child: SkeletonForm(fields: 1, actions: false),
                  ),
                ),
                const SkeletonForm(
                  fields: 1,
                  fieldHeights: {0: 80},
                  actions: false,
                ),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 260,
                    child: SkeletonForm(
                      fields: 1,
                      helperLines: {0: 2},
                      actions: false,
                    ),
                  ),
                ),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SkeletonButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class DetailLoadingSkeleton extends StatelessWidget {
  const DetailLoadingSkeleton({
    super.key,
    this.inCard = true,
    this.lines = 4,
    this.items = true,
    this.actions = true,
  });
  final bool inCard;
  final int lines;
  final bool items;
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonText(lineHeight: 24, lastLineWidth: 0.6),
        const SizedBox(height: 16),
        for (var i = 0; i < lines; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: const Row(
              children: [
                Expanded(flex: 4, child: SkeletonText(lineHeight: 13)),
                SizedBox(width: 16),
                Expanded(flex: 6, child: SkeletonText()),
              ],
            ),
          ),
        if (items) ...[
          const SizedBox(height: 20),
          const SkeletonList(rows: 3, inCard: false, padding: 12, badge: true),
        ],
        if (actions) ...[
          const SizedBox(height: 16),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [SkeletonButton(), SkeletonButton()],
          ),
        ],
      ],
    );
    return SkeletonRegion(child: inCard ? SurfaceCard(child: body) : body);
  }
}

/// Geometry mirrors the dashboard's role-dependent hero and AdaptiveGrid.
class DashboardLoadingSkeleton extends StatelessWidget {
  const DashboardLoadingSkeleton({
    super.key,
    required this.compact,
    required this.metrics,
    this.hero = true,
    this.activity = false,
  });
  final bool compact;
  final int metrics;
  final bool hero;
  final bool activity;

  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        if (hero) ...[
          SurfaceCard(
            padding: compact ? 22 : 30,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 164 : 172),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SkeletonText(lastLineWidth: 0.4),
                  const SizedBox(height: 10),
                  SkeletonText(
                    lineHeight: compact ? 39.6 : 55,
                    lastLineWidth: 0.66,
                  ),
                  const SizedBox(height: 12),
                  const SkeletonText(lineHeight: 13, lastLineWidth: 0.35),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SkeletonStats(count: metrics, minimumWidth: compact ? 150 : 220),
        if (activity) ...[
          const SizedBox(height: 16),
          const RecordListSkeleton(rows: 3, avatar: true, rowHeight: 76),
        ],
      ],
    ),
  );
}

/// The two independently fetched chart cards keep their slot below available KPIs.
class ChartsLoadingSkeleton extends StatelessWidget {
  const ChartsLoadingSkeleton({super.key, this.height = 180});
  final double height;
  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: LayoutBuilder(
      builder: (context, box) {
        final first = SkeletonChart(height: height);
        final second = SkeletonChart(height: height);
        if (box.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: first),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: second),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        );
      },
    ),
  );
}

class ReportLoadingSkeleton extends StatelessWidget {
  const ReportLoadingSkeleton({
    super.key,
    this.metrics = 5,
    this.chart = false,
  });
  final int metrics;
  final bool chart;
  @override
  Widget build(BuildContext context) => SkeletonRegion(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonStats(
          count: metrics,
          minimumWidth: 150,
          maxColumns: 7,
          gap: 12,
        ),
        const SizedBox(height: 16),
        if (chart) ...[
          const ChartsLoadingSkeleton(),
          const SizedBox(height: 16),
        ],
        const RecordListSkeleton(rows: 3),
      ],
    ),
  );
}

class PlatformOverviewLoadingSkeleton extends StatelessWidget {
  const PlatformOverviewLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 768;
    return SkeletonRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonStats(
            count: 8,
            minimumWidth: narrow ? 150 : 200,
            gap: narrow ? 10 : 16,
          ),
          const SizedBox(height: 16),
          SkeletonStats(
            count: 2,
            minimumWidth: narrow ? 150 : 300,
            maxColumns: 2,
            gap: narrow ? 10 : 16,
          ),
          const SizedBox(height: 28),
          const RecordListSkeleton(rows: 3),
        ],
      ),
    );
  }
}

class PageLoadingSkeleton extends StatelessWidget {
  const PageLoadingSkeleton({
    super.key,
    this.maxWidth = 760,
    this.form = false,
  });
  final double maxWidth;
  final bool form;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    padding: const EdgeInsets.all(16),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: form
            ? const SkeletonForm(fields: 6)
            : const DetailLoadingSkeleton(),
      ),
    ),
  );
}
