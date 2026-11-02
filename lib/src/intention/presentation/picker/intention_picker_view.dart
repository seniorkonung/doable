import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../long_term_relation/application/intention_relation_group.dart';
import '../../../long_term_relation/application/relation_pair_probe.dart';
import '../../../long_term_relation/presentation/relation_group_name.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_view_model.dart';
import '../catalog/intention_tag_conditions_view_model.dart';
import '../search/intention_list_header.dart';
import '../search/intention_search_bar.dart';
import '../search/intention_search_kind.dart';
import '../search/intention_search_list.dart';
import 'intention_picker_purpose_sheet.dart';
import 'intention_picker_row.dart';

/// Экран выбора намерения назначения [purpose]: крестик с заголовком, поле
/// поиска, фильтр по тегам и заголовок списка закреплены над выдачей.
/// С [purposeDescription] под заголовком стоит строка назначения, которая
/// открывает лист «Что вы выбираете».
///
/// Под шапкой экран собран из общих частей модуля поиска: строки поиска,
/// заголовка списка и выдачи.
///
/// Экран не знает маршрутов, права запуска и типа результата: о закрытии,
/// выборе и открытии подробностей страница узнаёт из обработчиков.
final class IntentionPickerView extends ConsumerStatefulWidget {
  const IntentionPickerView({
    required this.purpose,
    required this.closeLabel,
    required this.emptyScopeMessage,
    required this.onClose,
    required this.rowBehavior,
    required this.onOpenDetails,
    this.purposeDescription,
    this.notice,
    this.footer,
    super.key,
  });

  final IntentionPickerPurpose purpose;

  /// Назначение, которое страница напоминает пользователю; без него шапка
  /// показывает только заголовок.
  final IntentionPickerPurposeDescription? purposeDescription;

  /// Доступное название крестика: его смысл для вызвавшего потока знает
  /// страница.
  final String closeLabel;

  /// Сообщение страницы о том, что допустимый охват пуст.
  final String emptyScopeMessage;

  final VoidCallback onClose;

  final IntentionPickerRowBehavior rowBehavior;
  final void Function(IntentionId id) onOpenDetails;

  /// Отказ экрана под выдачей.
  final Widget? notice;

  /// Закреплённая нижняя часть: сообщения приложения [Scaffold] ставит над ней.
  final Widget? footer;

  @override
  ConsumerState<IntentionPickerView> createState() =>
      _IntentionPickerViewState();
}

/// Поведение строк выбирается вызывающей страницей целиком.
sealed class IntentionPickerRowBehavior {
  const IntentionPickerRowBehavior();
}

final class IntentionPickerSingle extends IntentionPickerRowBehavior {
  const IntentionPickerSingle({required this.onPick});
  final void Function(GraphSnapshot<IntentionSummary>) onPick;
}

final class IntentionPickerCheckable extends IntentionPickerRowBehavior {
  const IntentionPickerCheckable({
    required this.group,
    required this.selectedIds,
    required this.onToggle,
  });
  final IntentionRelationGroup group;
  final Set<IntentionId> selectedIds;
  final void Function(GraphSnapshot<IntentionSummary>) onToggle;
}

final class _IntentionPickerViewState
    extends ConsumerState<IntentionPickerView> {
  final _titleController = TextEditingController();
  bool _purposeExpanded = false;

  Future<void> _openPurpose(
    IntentionPickerPurposeDescription description,
  ) async {
    setState(() => _purposeExpanded = true);
    await showIntentionPickerPurposeSheet(context, description);
    if (mounted) setState(() => _purposeExpanded = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = IntentionSearchKind.of(widget.purpose);
    final keyPrefix = kind.keyPrefix;
    final catalogProvider = intentionCatalogViewModelProvider(widget.purpose);
    final conditionsProvider = intentionTagConditionsViewModelProvider(
      widget.purpose,
    );
    final title = kind.title(l10n);
    final purposeDescription = widget.purposeDescription;
    return Scaffold(
      appBar: purposeDescription == null
          ? TopBar(
              closeKey: ValueKey('$keyPrefix-cancel'),
              title: title,
              closeLabel: widget.closeLabel,
              onClose: widget.onClose,
            )
          : TopBar.withPurpose(
              context,
              closeKey: ValueKey('$keyPrefix-cancel'),
              title: title,
              closeLabel: widget.closeLabel,
              onClose: widget.onClose,
              purpose: TopBarPurpose(
                subtitle: purposeDescription.subtitle,
                label: l10n.intentionPickerPurposeLabel(
                  title,
                  purposeDescription.subtitle,
                ),
                expanded: _purposeExpanded,
                onOpen: () => unawaited(_openPurpose(purposeDescription)),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                DoableMetrics.space2,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: IntentionSearchBar(
                purpose: widget.purpose,
                controller: _titleController,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                0,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: IntentionListHeader(purpose: widget.purpose),
            ),
            Expanded(
              child: IntentionSearchList(
                purpose: widget.purpose,
                rowBuilder: (context, results, summary) {
                  final key = ValueKey(
                    '$keyPrefix-${summary.id.toCanonicalString()}',
                  );
                  final snapshot = GraphSnapshot(
                    value: summary,
                    revision: results.revision,
                  );
                  final occupant = results.pairOccupants[summary.id];
                  void openPage() => widget.onOpenDetails(summary.id);
                  return switch (widget.rowBehavior) {
                    IntentionPickerSingle(:final onPick) => IntentionPickerRow(
                      key: key,
                      purpose: widget.purpose,
                      summary: summary,
                      requiredTagIds: results.query.tagFilter.requiredTagIds,
                      onPick: () => onPick(snapshot),
                      onOpenPage: openPage,
                    ),
                    IntentionPickerCheckable(
                      :final group,
                      :final selectedIds,
                      :final onToggle,
                    ) =>
                      occupant == null
                          ? IntentionPickerRow.checkable(
                              key: key,
                              purpose: widget.purpose,
                              summary: summary,
                              requiredTagIds:
                                  results.query.tagFilter.requiredTagIds,
                              chosen: selectedIds.contains(summary.id),
                              onPick: () => onToggle(snapshot),
                              onOpenPage: openPage,
                            )
                          : IntentionPickerRow.occupied(
                              key: key,
                              purpose: widget.purpose,
                              summary: summary,
                              reason: relationPairReasonName(
                                l10n,
                                RelationPairReason.from(
                                  group: group,
                                  occupant: occupant,
                                ),
                              ),
                              onOpenPage: openPage,
                            ),
                  };
                },
                emptyScope: (_) => EmptyState(
                  title: l10n.intentionPickerEmptyScopeTitle,
                  text: widget.emptyScopeMessage,
                ),
                onResetFilters: () {
                  _titleController.clear();
                  ref.read(catalogProvider.notifier).clearTitleFilter();
                  ref.read(conditionsProvider.notifier).clear();
                },
                bottomPadding: DoableMetrics.space10,
              ),
            ),
            if (widget.notice case final notice?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DoableMetrics.space5,
                  DoableMetrics.space2,
                  DoableMetrics.space5,
                  DoableMetrics.space2,
                ),
                child: notice,
              ),
          ],
        ),
      ),
      // https://api.flutter.dev/flutter/material/Scaffold/bottomNavigationBar.html
      bottomNavigationBar: widget.footer,
    );
  }
}
