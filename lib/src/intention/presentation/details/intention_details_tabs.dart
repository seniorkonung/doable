import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/tabs.dart';
import '../../../design_system/doable_icon.dart';
import '../../../long_term_relation/application/relation_counts.dart';

enum IntentionDetailsTab { overview, relations, choices, statistics }

/// Разделы страницы намерения с числами из сводки подробных данных.
final class IntentionDetailsTabs extends StatelessWidget {
  const IntentionDetailsTabs({
    required this.value,
    required this.onChange,
    required this.counts,
    required this.headHidden,
    super.key,
  });

  final IntentionDetailsTab value;
  final ValueChanged<IntentionDetailsTab> onChange;
  final RelationCounts counts;
  final ValueListenable<bool> headHidden;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    // Закрепление под панелью обеспечивает сама прокрутка:
    // https://api.flutter.dev/flutter/widgets/SliverPersistentHeader-class.html
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabsHeader(
        height: Tabs.heightFor(context),
        child: ValueListenableBuilder(
          valueListenable: headHidden,
          builder: (context, stuck, _) => Tabs(
            stuck: stuck,
            label: texts.detailsTabsLabel,
            value: value,
            onChange: onChange,
            items: [
              TabItem(
                id: IntentionDetailsTab.overview,
                label: texts.detailsOverviewTab,
                semanticLabel: texts.detailsOverviewTab,
              ),
              TabItem(
                id: IntentionDetailsTab.relations,
                label: texts.detailsRelationsTab,
                semanticLabel: texts.detailsRelationsTabSemantic(
                  counts.active,
                  counts.archived,
                ),
                count: counts.active,
                icon: counts.archived > 0 ? DoableIconData.archive : null,
              ),
              TabItem(
                id: IntentionDetailsTab.choices,
                label: texts.detailsChoicesTab,
                semanticLabel: texts.detailsChoicesTab,
              ),
              TabItem(
                id: IntentionDetailsTab.statistics,
                label: texts.statisticsSectionTitle,
                semanticLabel: texts.statisticsSectionTitle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

/// Сохраняет место под вкладками, чтобы короткое тело не раскрывало шапку.
final class IntentionDetailsTabBody extends StatelessWidget {
  const IntentionDetailsTabBody({required this.slivers, super.key});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final bodyStart = constraints.precedingScrollExtent;
      final tabsHeight = Tabs.heightFor(context);
      return SliverMainAxisGroup(
        slivers: [
          ...slivers,
          SliverLayoutBuilder(
            builder: (context, constraints) {
              // Остаток считаем по раскладке sliver'ов, без измерения строк:
              // https://api.flutter.dev/flutter/rendering/SliverConstraints/precedingScrollExtent.html
              final bodyExtent = constraints.precedingScrollExtent - bodyStart;
              return SliverToBoxAdapter(
                child: SizedBox(
                  height: math.max(
                    24,
                    constraints.viewportMainAxisExtent -
                        tabsHeight -
                        bodyExtent,
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
  );
}
