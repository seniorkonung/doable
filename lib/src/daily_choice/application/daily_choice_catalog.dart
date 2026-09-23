import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../domain/calendar_date.dart';
import '../domain/daily_choice_id.dart';

enum DailyChoiceCatalogQueryValidationFailure { pageSizeOutOfRange }

final class DailyChoiceCatalogQueryValidationException implements Exception {
  const DailyChoiceCatalogQueryValidationException(this.failure);

  final DailyChoiceCatalogQueryValidationFailure failure;
}

/// Продолжение принадлежит одному репозиторию, фильтрам, размеру порции,
/// эпохе, ревизии и последнему ключу порядка. Содержимое скрыто от клиента.
abstract interface class DailyChoiceCatalogCursor {}

final class DailyChoiceCatalogQuery {
  factory DailyChoiceCatalogQuery({
    CalendarDate? date,
    bool? isCompleted,
    int pageSize = defaultPageSize,
    DailyChoiceCatalogCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const DailyChoiceCatalogQueryValidationException(
        DailyChoiceCatalogQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return DailyChoiceCatalogQuery._(date, isCompleted, pageSize, cursor);
  }

  const DailyChoiceCatalogQuery._(
    this.date,
    this.isCompleted,
    this.pageSize,
    this.cursor,
  );

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  /// null означает все календарные даты.
  final CalendarDate? date;

  /// null означает оба состояния выполнения.
  final bool? isCompleted;
  final int pageSize;
  final DailyChoiceCatalogCursor? cursor;
}

/// Текущие данные прямого участника, нужные для краткой формулировки.
final class DailyChoiceCatalogParticipant {
  factory DailyChoiceCatalogParticipant({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
    required IntentionReadiness readiness,
  }) => DailyChoiceCatalogParticipant._(
    id: id,
    title: IntentionText.normalizeTitle(title),
    archiveState: archiveState,
    readiness: readiness,
  );

  const DailyChoiceCatalogParticipant._({
    required this.id,
    required this.title,
    required this.archiveState,
    required this.readiness,
  });

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
  final IntentionReadiness readiness;
}

/// Проверенная краткая проекция. Путь и технический ключ порядка остаются
/// внутри репозитория; одинаковые данные разных id остаются отдельными.
final class DailyChoiceCatalogItem {
  factory DailyChoiceCatalogItem({
    required DailyChoiceId id,
    required DailyChoiceCatalogParticipant source,
    required DailyChoiceCatalogParticipant selected,
    required CalendarDate date,
    required bool isCompleted,
  }) {
    if (source.id == selected.id) {
      throw ArgumentError.value(selected.id, 'selected');
    }
    return DailyChoiceCatalogItem._(
      id: id,
      source: source,
      selected: selected,
      date: date,
      isCompleted: isCompleted,
    );
  }

  const DailyChoiceCatalogItem._({
    required this.id,
    required this.source,
    required this.selected,
    required this.date,
    required this.isCompleted,
  });

  final DailyChoiceId id;
  final DailyChoiceCatalogParticipant source;
  final DailyChoiceCatalogParticipant selected;
  final CalendarDate date;
  final bool isCompleted;
}

/// Репозиторий выдаёт записи по date DESC, creation_sequence DESC.
/// Список и ревизия относятся к одному подтверждённому снимку.
sealed class DailyChoiceCatalogPage {
  DailyChoiceCatalogPage({
    required List<DailyChoiceCatalogItem> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);

  final List<DailyChoiceCatalogItem> items;
  final DailyChoiceCatalogCursor? nextCursor;
  final GraphRevision revision;
}

/// Точное количество и строки первой порции получены на одной ревизии.
final class DailyChoiceCatalogFirstPage extends DailyChoiceCatalogPage {
  DailyChoiceCatalogFirstPage({
    required super.items,
    required int totalCount,
    required super.nextCursor,
    required super.revision,
  }) : totalCount = _checkedCount(totalCount, items.length);

  final int totalCount;

  static int _checkedCount(int count, int itemCount) {
    if (count < itemCount) {
      throw const DailyChoiceCatalogPageValidationException();
    }
    return count;
  }
}

final class DailyChoiceCatalogPageValidationException implements Exception {
  const DailyChoiceCatalogPageValidationException();
}

final class DailyChoiceCatalogContinuationPage extends DailyChoiceCatalogPage {
  DailyChoiceCatalogContinuationPage({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}

sealed class DailyChoiceCatalogReadFailure implements GraphCommandFailure {
  const DailyChoiceCatalogReadFailure();
}

/// Чужой курсор либо продолжение с другими фильтрами или размером порции.
final class DailyChoiceCatalogValidationFailure
    extends DailyChoiceCatalogReadFailure {
  const DailyChoiceCatalogValidationFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Ревизия или эпоха продолжения больше не совпадает с текущим снимком.
final class DailyChoiceCatalogSnapshotExpired
    extends DailyChoiceCatalogReadFailure {
  const DailyChoiceCatalogSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class DailyChoiceCatalogUnavailableFailure
    extends DailyChoiceCatalogReadFailure {
  const DailyChoiceCatalogUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class DailyChoiceCatalogCorruptionFailure
    extends DailyChoiceCatalogReadFailure {
  const DailyChoiceCatalogCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class DailyChoiceCatalogUnexpectedFailure
    extends DailyChoiceCatalogReadFailure {
  const DailyChoiceCatalogUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef DailyChoiceCatalogPageResult =
    GraphResult<DailyChoiceCatalogPage, DailyChoiceCatalogReadFailure>;
typedef DailyChoiceCatalogPageSuccess =
    GraphResultSuccess<DailyChoiceCatalogPage, DailyChoiceCatalogReadFailure>;
typedef DailyChoiceCatalogPageError =
    GraphResultFailure<DailyChoiceCatalogPage, DailyChoiceCatalogReadFailure>;
