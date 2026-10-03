import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/favorite_order.dart';

/// Перемещает избранное намерение в едином порядке избранных.
///
/// Команда адресует перемещаемое намерение и опору только идентификаторами:
/// индексов видимого списка, названий и мест хранения в ней нет.
///
/// Исполняется через `PersonalGraphRepository.execute` общим
/// последовательным исполнителем личного графа. В одной транзакции
/// исполнитель читает полный порядок, включая архивированные избранные
/// намерения, проверяет актуальность участников и вычисляет новый порядок
/// функцией [moveInFavoriteOrder]; проверка атомарна с записью:
///
/// - перемещаемое намерение указано собственной опорой —
///   [FavoriteOrderInputFailure];
/// - перемещаемое или опорное намерение не избранное либо удалено —
///   [FavoriteOrderConflictFailure] без записи. Архивирование участника
///   допустимо: архивированное избранное сохраняет место;
/// - фактическая перестановка — [FavoriteOrderMoved]. Успех возвращается
///   только после commit, а ревизия продвигается ровно на единицу;
/// - перемещение без видимого изменения — [FavoriteOrderUnchanged] на текущей
///   ревизии, без записи и продвижения ревизии;
/// - недоступность, повреждение и неизвестный отказ не продвигают ревизию и
///   не оставляют частичной записи.
///
/// Ни один исход не меняет данные намерений и их показания времени,
/// поисковую проекцию, долговременные связи, теги и дневные выборы, поэтому
/// пакет изменения не содержит мутаций намерений.
final class MoveFavoriteIntention
    implements
        GraphCommand<FavoriteOrderCommandSuccess, FavoriteOrderCommandFailure> {
  const MoveFavoriteIntention({
    required this.intentionId,
    required this.placement,
  });

  final IntentionId intentionId;
  final FavoritePlacement placement;
}

/// Один факт об едином порядке избранных на общей ревизии личного графа.
/// Состав и порядок факт не перечисляет: потребители перечитывают полный
/// снимок списка не старше [revision].
sealed class FavoriteOrderChange implements GraphChange {
  const FavoriteOrderChange();
}

/// Подтверждённое изменение порядка на новой ревизии.
final class FavoriteOrderChangedChange extends FavoriteOrderChange {
  const FavoriteOrderChangedChange({required this.revision});

  @override
  final GraphRevision revision;
}

/// Подтверждение прежнего порядка на текущей ревизии без её продвижения.
final class FavoriteOrderUnchangedChange extends FavoriteOrderChange {
  const FavoriteOrderUnchangedChange({required this.revision});

  @override
  final GraphRevision revision;
}

/// Каждому исходу соответствует ровно одно изменение порядка.
sealed class FavoriteOrderCommandSuccess implements GraphCommandOutcome {
  const FavoriteOrderCommandSuccess();

  FavoriteOrderChange get change;

  @override
  Iterable<GraphChange> get changes => [change];
}

final class FavoriteOrderMoved extends FavoriteOrderCommandSuccess {
  const FavoriteOrderMoved(this.change);

  @override
  final FavoriteOrderChangedChange change;
}

final class FavoriteOrderUnchanged extends FavoriteOrderCommandSuccess {
  const FavoriteOrderUnchanged(this.change);

  @override
  final FavoriteOrderUnchangedChange change;
}

sealed class FavoriteOrderCommandFailure implements GraphCommandFailure {
  const FavoriteOrderCommandFailure();

  /// Отказ контракта для перемещения, отклонённого правилом порядка.
  factory FavoriteOrderCommandFailure.rejected(
    FavoriteOrderMoveRejected rejection,
  ) => switch (rejection) {
    FavoriteOrderMoveSelfAnchored() => const FavoriteOrderInputFailure(),
    FavoriteOrderMoveMissingParticipant() =>
      const FavoriteOrderConflictFailure(),
  };
}

/// Перемещаемое намерение указано собственной опорой.
final class FavoriteOrderInputFailure extends FavoriteOrderCommandFailure {
  const FavoriteOrderInputFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Перемещаемое или опорное намерение к моменту исполнения не избранное
/// либо удалено; порядок не изменён.
final class FavoriteOrderConflictFailure extends FavoriteOrderCommandFailure {
  const FavoriteOrderConflictFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class FavoriteOrderUnavailableFailure
    extends FavoriteOrderCommandFailure {
  const FavoriteOrderUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class FavoriteOrderCorruptionFailure extends FavoriteOrderCommandFailure {
  const FavoriteOrderCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class FavoriteOrderUnexpectedFailure extends FavoriteOrderCommandFailure {
  const FavoriteOrderUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef FavoriteOrderCommandResult =
    GraphCommandResult<
      FavoriteOrderCommandSuccess,
      FavoriteOrderCommandFailure
    >;
typedef FavoriteOrderCommandSucceeded =
    GraphCommandSucceeded<
      FavoriteOrderCommandSuccess,
      FavoriteOrderCommandFailure
    >;
typedef FavoriteOrderCommandFailed =
    GraphCommandFailed<
      FavoriteOrderCommandSuccess,
      FavoriteOrderCommandFailure
    >;
