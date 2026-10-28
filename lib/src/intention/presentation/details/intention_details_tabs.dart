import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/tabs.dart';
import '../../../design_system/doable_icon.dart';
import '../../../long_term_relation/application/relation_counts.dart';

enum IntentionDetailsTab { overview, relations, statistics }

/// Разделы страницы намерения с числами из сводки подробных данных.
final class IntentionDetailsTabs extends StatelessWidget {
  const IntentionDetailsTabs({
    required this.value,
    required this.onChange,
    required this.counts,
    super.key,
  });

  final IntentionDetailsTab value;
  final ValueChanged<IntentionDetailsTab> onChange;
  final RelationCounts counts;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    // Закрепление под панелью обеспечивает сама прокрутка:
    // https://api.flutter.dev/flutter/widgets/SliverPersistentHeader-class.html
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabsHeader(
        height: Tabs.heightFor(context),
        child: Tabs(
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
              id: IntentionDetailsTab.statistics,
              label: texts.statisticsSectionTitle,
              semanticLabel: texts.statisticsSectionTitle,
            ),
          ],
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
