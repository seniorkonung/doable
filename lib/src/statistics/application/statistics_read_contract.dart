import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import 'contribution_counts.dart';
import 'statistics_period.dart';

/// Виды по сохранённому пути в порядке показа на Главной.
enum StatisticsView {
  sourceIntentions,
  intermediateIntentions,
  selectedActions,
}

enum StatisticsQueryValidationFailure { pageSizeOutOfRange }

final class StatisticsQueryValidationException implements Exception {
  const StatisticsQueryValidationException(this.failure);

  final StatisticsQueryValidationFailure failure;
}

/// Непрозрачное продолжение, связанное с периодом, видом, местной датой,
/// размером порции, ревизией (включая эпоху) и последним ключом порядка.
/// Курсор не сериализуется; смена любой привязки требует первой порции.
abstract interface class StatisticsCursor {}

final class StatisticsQuery {
  factory StatisticsQuery({
    required StatisticsPeriod period,
    required StatisticsView view,
    required CalendarDate localDate,
    required int pageSize,
    StatisticsCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const StatisticsQueryValidationException(
        StatisticsQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return StatisticsQuery._(period, view, localDate, pageSize, cursor);
  }

  const StatisticsQuery._(
    this.period,
    this.view,
    this.localDate,
    this.pageSize,
    this.cursor,
  );

  static const minPageSize = 1;
  static const maxPageSize = 100;

  final StatisticsPeriod period;
  final StatisticsView view;
  final CalendarDate localDate;
  final int pageSize;
  final StatisticsCursor? cursor;
}

/// Намерение с хотя бы одним запланированным вкладом выбранного вида.
/// Название и архивное состояние относятся к ревизии порции.
final class StatisticsItem {
  factory StatisticsItem({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
    required ContributionCounts counts,
  }) {
    if (counts.planned == 0) {
      throw const StatisticsDataValidationException();
    }
    return StatisticsItem._(
      id,
      IntentionText.normalizeTitle(title),
      archiveState,
      counts,
    );
  }

  const StatisticsItem._(this.id, this.title, this.archiveState, this.counts);

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
  final ContributionCounts counts;
}

sealed class StatisticsPage {
  StatisticsPage({
    required List<StatisticsItem> items,
    required this.revision,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<StatisticsItem> items;
  final GraphRevision revision;

  /// null означает конец выдачи на этой ревизии.
  final StatisticsCursor? nextCursor;
}

final class StatisticsFirstPage extends StatisticsPage {
  StatisticsFirstPage({
    required this.summary,
    required this.totalItems,
    required super.items,
    required super.revision,
    required super.nextCursor,
  }) {
    if (totalItems < 0) {
      throw const StatisticsDataValidationException();
    }
  }

  final StatisticsPeriodSummary summary;
  final int totalItems;
}

final class StatisticsContinuationPage extends StatisticsPage {
  StatisticsContinuationPage({
    required super.items,
    required super.revision,
    required super.nextCursor,
  });
}

sealed class StatisticsReadFailure implements GraphCommandFailure {
  const StatisticsReadFailure();
}

/// Продолжение утратило привязку к условиям или снимку: нужна первая порция,
/// а не повтор прежнего курсора на новой ревизии.
final class StatisticsSnapshotExpired extends StatisticsReadFailure {
  const StatisticsSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class StatisticsReadUnavailableFailure extends StatisticsReadFailure {
  const StatisticsReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class StatisticsReadCorruptionFailure extends StatisticsReadFailure {
  const StatisticsReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class StatisticsReadUnexpectedFailure extends StatisticsReadFailure {
  const StatisticsReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef StatisticsPageResult =
    GraphResult<StatisticsPage, StatisticsReadFailure>;
typedef StatisticsPageSuccess =
    GraphResultSuccess<StatisticsPage, StatisticsReadFailure>;
typedef StatisticsPageError =
    GraphResultFailure<StatisticsPage, StatisticsReadFailure>;

/// Контракт чтения статистики Главной за единой границей личного графа.
abstract interface class StatisticsReadContract {
  /// Без курсора возвращает [StatisticsFirstPage]: сводку всего периода,
  /// точное число элементов вида и первую порцию на одной ревизии.
  /// С курсором возвращает [StatisticsContinuationPage] на той же ревизии
  /// либо [StatisticsSnapshotExpired], включая смену эпохи или условий.
  ///
  /// Элементов не больше [StatisticsQuery.pageSize]; порядок — вклад,
  /// запланированный вклад, идентификатор намерения, всё по убыванию.
  /// Продолжения не повторяют и не пропускают элементы этого снимка.
  /// Каждый выбор, включая полный дубликат, учитывается самостоятельно:
  /// исходному, каждому промежуточному либо выбранному намерению по виду,
  /// независимо от готовности и архивирования участников и шагов пути.
  ///
  /// Местная дата разделяет невыполненное в сводке: раньше неё — пропущено,
  /// начиная с неё — предстоит. Пустой вид может иметь непустую сводку.
  /// Доля элемента вычисляется от вклада сводки; при нуле доли нет.
  /// Нескольким промежуточным намерениям выбор засчитывается целиком.
  ///
  /// Адаптер проверяет прочитанные числа и остальные необходимые значения;
  /// нарушение инвариантов даёт повреждение всего чтения без частичных чисел.
  /// Только доказанная недоступность допускает обычный повтор тех же условий;
  /// повреждение и неизвестный отказ — нет. Отказ не заменяется нулями.
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query);
}
