import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import 'action_list_item.dart';

/// Роль намерения в сохранённом пути действия. Намерение, которое одно
/// составляет путь, — и корневое, и конечное; промежуточное стоит строго
/// между ними.
enum IntentionActionRole { root, intermediate, terminal }

/// Продолжение несёт ревизию и последний ключ порядка. Содержимое скрыто от
/// клиента.
abstract interface class IntentionActionsCursor {}

/// Одна порция действий, в путях которых намерение играет [role]. Размер
/// порции ограничен [minPageSize]–[maxPageSize]; иначе выбрасывается
/// [RangeError].
final class IntentionActionsQuery {
  factory IntentionActionsQuery({
    required IntentionId intentionId,
    required IntentionActionRole role,
    int pageSize = defaultPageSize,
    IntentionActionsCursor? cursor,
  }) {
    RangeError.checkValueInInterval(pageSize, minPageSize, maxPageSize);
    return IntentionActionsQuery._(intentionId, role, pageSize, cursor);
  }

  const IntentionActionsQuery._(
    this.intentionId,
    this.role,
    this.pageSize,
    this.cursor,
  );

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final IntentionId intentionId;
  final IntentionActionRole role;
  final int pageSize;
  final IntentionActionsCursor? cursor;
}

/// Числа действий намерения за всё время, независимо от даты и выполнения.
final class IntentionActionCounts {
  const IntentionActionCounts({
    required this.root,
    required this.intermediate,
    required this.terminal,
    required this.total,
  });

  final int root;
  final int intermediate;
  final int terminal;

  /// Действия, в путях которых есть намерение, — каждое один раз.
  final int total;

  int countOf(IntentionActionRole role) => switch (role) {
    IntentionActionRole.root => root,
    IntentionActionRole.intermediate => intermediate,
    IntentionActionRole.terminal => terminal,
  };

  /// Роль с наибольшим числом действий; при равенстве — первая по порядку
  /// «корневое», «промежуточное», «конечное».
  IntentionActionRole get busiestRole {
    var busiest = IntentionActionRole.values.first;
    for (final role in IntentionActionRole.values.skip(1)) {
      if (countOf(role) > countOf(busiest)) busiest = role;
    }
    return busiest;
  }
}

/// Действия роли упорядочены по дате, затем по часу («Весь день» после
/// любого часа), затем по порядку создания — всё по убыванию. Строки и
/// ревизия относятся к одному подтверждённому снимку.
sealed class IntentionActionsPage {
  IntentionActionsPage({
    required List<ActionListItem> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);

  final List<ActionListItem> items;
  final IntentionActionsCursor? nextCursor;
  final GraphRevision revision;
}

/// Числа всех ролей и строки первой порции получены на одном снимке.
final class IntentionActionsFirstPage extends IntentionActionsPage {
  IntentionActionsFirstPage({
    required super.items,
    required this.counts,
    required super.nextCursor,
    required super.revision,
  });

  final IntentionActionCounts counts;
}

final class IntentionActionsContinuationPage extends IntentionActionsPage {
  IntentionActionsContinuationPage({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}

sealed class IntentionActionsReadFailure implements GraphCommandFailure {
  const IntentionActionsReadFailure();
}

/// Ревизия продолжения больше не совпадает с текущим снимком.
final class IntentionActionsSnapshotExpired
    extends IntentionActionsReadFailure {
  const IntentionActionsSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class IntentionActionsUnavailableFailure
    extends IntentionActionsReadFailure {
  const IntentionActionsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class IntentionActionsCorruptionFailure
    extends IntentionActionsReadFailure {
  const IntentionActionsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class IntentionActionsUnexpectedFailure
    extends IntentionActionsReadFailure {
  const IntentionActionsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef IntentionActionsPageResult =
    GraphResult<IntentionActionsPage, IntentionActionsReadFailure>;
typedef IntentionActionsPageSuccess =
    GraphResultSuccess<IntentionActionsPage, IntentionActionsReadFailure>;
typedef IntentionActionsPageError =
    GraphResultFailure<IntentionActionsPage, IntentionActionsReadFailure>;
