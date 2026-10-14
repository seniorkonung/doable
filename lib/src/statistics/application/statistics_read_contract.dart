import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import 'contribution_counts.dart';
import 'intention_statistics_breakdown.dart';
import 'intention_statistics_read_contract.dart';
import 'statistics_period.dart';

/// Виды статистики в порядке показа на Главной.
enum StatisticsView {
  sourceIntentions,
  intermediateIntentions,
  selectedActions,
  throughRelations,
}

enum StatisticsQueryValidationFailure { pageSizeOutOfRange }

final class StatisticsQueryValidationException implements Exception {
  const StatisticsQueryValidationException(this.failure);

  final StatisticsQueryValidationFailure failure;
}

/// Непрозрачное продолжение, связанное с периодом, видом, местной датой,
/// размером порции, ревизией (включая эпоху) и позицией в упорядоченной выдаче.
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

/// Продолжение утратило привязку к условиям или снимку либо снимок первой
/// порции «Через связи» или раздела устарел при подготовке или подсчёте.
/// Нужна новая первая порция или раздел, а не прежний курсор на новой ревизии.
/// Это сигнал согласования, а не недоступность, повреждение или неизвестный отказ.
final class StatisticsSnapshotExpired extends StatisticsReadFailure {
  const StatisticsSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

/// Намерение раздела отсутствует. Это не пустой период или вид.
/// Чтение Главной не возвращает этот отказ.
final class StatisticsIntentionNotFoundFailure extends StatisticsReadFailure {
  const StatisticsIntentionNotFoundFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
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

/// Контракт чтения статистики за единой границей личного графа.
abstract interface class StatisticsReadContract {
  /// Без курсора возвращает [StatisticsFirstPage]: сводку всего периода,
  /// точное число элементов вида и первую порцию на одной ревизии.
  /// С курсором возвращает [StatisticsContinuationPage] на той же ревизии
  /// либо [StatisticsSnapshotExpired], включая смену эпохи или условий.
  ///
  /// Первая порция «Через связи» также может вернуть [StatisticsSnapshotExpired],
  /// если её снимок утратил годность при подготовке или подсчёте.
  /// Один вызов выполняет одну попытку: адаптер не повторяет получение исходных
  /// данных, загрузку снимка или подсчёт. Новую первую порцию запрашивает
  /// потребитель после проверки времени жизни, видимости и поколения запроса.
  /// Сигнал не предъявляется как пользовательский отказ: прежние подтверждённые
  /// числа сохраняются с признаком обновления до согласованной замены.
  /// Скрытие, смена условий и освобождение потребителя делают запрос неактуальным;
  /// его поздний сигнал не меняет состояние и не запускает новых чтений.
  /// Уже выполняющаяся транзакция или подсчёт могут завершиться без отмены.
  ///
  /// Элементов не больше [StatisticsQuery.pageSize]; порядок — вклад,
  /// запланированный вклад, идентификатор намерения, всё по убыванию.
  /// Продолжения не повторяют и не пропускают элементы этого снимка.
  /// Каждый выбор, включая полный дубликат, учитывается самостоятельно:
  /// исходному, каждому промежуточному либо выбранному намерению по виду,
  /// независимо от готовности и архивирования участников и шагов пути.
  /// Через связи выбор засчитывается всем намерениям сохранённого пути и всем,
  /// от кого к ним ведут текущие активные связи. Несколько цепочек и циклы
  /// не умножают вклад одного выбора в одно намерение.
  ///
  /// Местная дата разделяет невыполненное в сводке: раньше неё — пропущено,
  /// начиная с неё — предстоит. Пустой вид может иметь непустую сводку.
  /// Доля элемента вычисляется от вклада сводки; при нуле доли нет.
  /// Каждому засчитанному намерению выбор достаётся целиком: сумма долей
  /// промежуточных намерений и вида «Через связи» не нормализуется к 100%.
  ///
  /// Адаптер проверяет прочитанные числа и остальные необходимые значения;
  /// нарушение инвариантов даёт повреждение всего чтения без частичных чисел.
  /// Только доказанная недоступность допускает обычный повтор тех же условий;
  /// повреждение и неизвестный отказ — нет. Отказ не заменяется нулями.
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query);

  /// Возвращает четыре карточки, сводку выбранного вида, календарь и первые
  /// порции допустимых разбивок на одной ревизии личного графа.
  /// [StatisticsIntentionNotFoundFailure] отличается от успешного раздела
  /// существующего намерения без засчитанных выборов.
  ///
  /// Один вызов выполняет одну согласованную попытку без внутренних повторов
  /// исходных данных, снимка или подсчёта. При [StatisticsSnapshotExpired]
  /// новый раздел запрашивает только живой, видимый потребитель актуального
  /// поколения. Поздний ответ после скрытия, смены условий или освобождения
  /// не запускает чтений; выполняющаяся транзакция или подсчёт могут завершиться.
  /// До согласованной замены потребитель сохраняет прежние подтверждённые
  /// числа с признаком обновления, не предъявляя устаревание как отказ.
  /// Категории остальных отказов и допустимость обычного повтора следуют
  /// [getStatisticsPage]; частичный результат или ложные нули не возвращаются.
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  );

  /// Продолжает одну разбивку с условиями, типом строк, размером порции
  /// и ревизией исходного раздела, закреплёнными в [cursor].
  /// Порядок, предел размера и отсутствие повторов или пропусков заданы
  /// [StatisticsBreakdownPage]. При смене ревизии, эпохи или утрате результата
  /// возвращает [StatisticsSnapshotExpired], не пересчитывая раздел.
  /// Потребитель получает новую основу по [getIntentionStatisticsSection],
  /// а остальные отказы сохраняют уже загруженные строки.
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor);
}
