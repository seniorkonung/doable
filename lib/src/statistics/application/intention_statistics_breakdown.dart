import '../../graph/application/graph_revision.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'contribution_counts.dart';
import 'statistics_read_contract.dart';

enum StatisticsBreakdown { sourceIntentions, selectedActions, relations }

extension StatisticsViewBreakdowns on StatisticsView {
  /// Только допустимые разбивки, в порядке показа в разделе намерения.
  List<StatisticsBreakdown> get breakdowns => switch (this) {
    StatisticsView.sourceIntentions => const [
      StatisticsBreakdown.selectedActions,
    ],
    StatisticsView.intermediateIntentions => const [
      StatisticsBreakdown.sourceIntentions,
      StatisticsBreakdown.selectedActions,
    ],
    StatisticsView.selectedActions => const [
      StatisticsBreakdown.sourceIntentions,
    ],
    StatisticsView.throughRelations => const [
      StatisticsBreakdown.relations,
      StatisticsBreakdown.selectedActions,
    ],
  };
}

/// Связь обозначается связанным намерением, но сохраняет собственные
/// идентификатор и архивное состояние. Количества [relatedIntention] относятся
/// к выборам, засчитанным этой связи, а не ко всей статистике её намерения.
final class StatisticsRelationItem {
  const StatisticsRelationItem({
    required this.id,
    required this.scope,
    required this.relatedIntention,
  });

  final LongTermRelationId id;
  final RelationScope scope;
  final StatisticsItem relatedIntention;
}

/// Непрозрачное продолжение разбивки. Адаптер связывает его с намерением,
/// периодом, видом, разбивкой, местной датой, размером порции, ревизией
/// (включая эпоху) и позицией. Продолжение принимает только этот курсор,
/// поэтому новые условия требуют нового чтения раздела.
///
/// Курсор не сериализуется и не удерживает вытесненный вычисленный результат.
/// Смена ревизии или утрата результата даёт [StatisticsSnapshotExpired].
/// Тип строки сохраняется от первой порции до всех её продолжений.
abstract interface class StatisticsBreakdownCursor<T> {}

/// Строки идут по убыванию вклада, запланированного вклада и идентификатора:
/// намерения для [StatisticsItem], связи для [StatisticsRelationItem].
/// Адаптер возвращает не больше запрошенного размера порции (до 100),
/// без повторов и пропусков между порциями одного снимка.
///
/// Доля строки — её вклад / вклад намерения раздела в выбранном виде;
/// при нулевом знаменателе доли нет. Доли связей не нормализуются к 100%.
sealed class StatisticsBreakdownPage<T> {
  StatisticsBreakdownPage({required List<T> items, required this.nextCursor})
    : items = List.unmodifiable(items) {
    if (this.items.length > StatisticsQuery.maxPageSize) {
      throw const StatisticsDataValidationException();
    }
  }

  final List<T> items;

  /// null означает конец этой разбивки на её снимке.
  final StatisticsBreakdownCursor<T>? nextCursor;
}

/// Первая порция входит в составной результат раздела и использует его
/// единственную ревизию. Точное число элементов известно до подгрузки.
final class StatisticsBreakdownFirstPage<T> extends StatisticsBreakdownPage<T> {
  StatisticsBreakdownFirstPage({
    required super.items,
    required this.totalItems,
    required super.nextCursor,
  }) {
    if (totalItems < items.length) {
      throw const StatisticsDataValidationException();
    }
  }

  final int totalItems;
}

/// Продолжение принадлежит ревизии исходного раздела либо чтение возвращает
/// [StatisticsSnapshotExpired]. Оно не повторяет сводку и число элементов.
final class StatisticsBreakdownContinuationPage<T>
    extends StatisticsBreakdownPage<T> {
  StatisticsBreakdownContinuationPage({
    required super.items,
    required this.revision,
    required super.nextCursor,
  });

  final GraphRevision revision;
}
