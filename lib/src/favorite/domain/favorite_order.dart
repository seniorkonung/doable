import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';

/// Место избранного намерения в едином порядке вместе с его архивным
/// состоянием. Архивированное избранное намерение скрыто на Главной, но
/// сохраняет своё место.
final class FavoriteOrderEntry {
  const FavoriteOrderEntry({
    required this.intentionId,
    required this.archiveState,
  });

  final IntentionId intentionId;
  final IntentionArchiveState archiveState;

  bool get isActive => archiveState == IntentionArchiveState.active;

  @override
  bool operator ==(Object other) =>
      other is FavoriteOrderEntry &&
      other.intentionId == intentionId &&
      other.archiveState == archiveState;

  @override
  int get hashCode => Object.hash(intentionId, archiveState);
}

enum FavoriteOrderValidationFailure { duplicateIntention }

final class FavoriteOrderValidationException implements Exception {
  const FavoriteOrderValidationException(this.failure);

  final FavoriteOrderValidationFailure failure;
}

/// Полный однозначный порядок всех избранных намерений, включая
/// архивированные: каждое намерение занимает ровно одно место.
final class FavoriteOrder {
  factory FavoriteOrder(Iterable<FavoriteOrderEntry> entries) {
    final immutableEntries = List<FavoriteOrderEntry>.unmodifiable(entries);
    final intentionIds = List<IntentionId>.unmodifiable(
      immutableEntries.map((entry) => entry.intentionId),
    );
    if (intentionIds.toSet().length != intentionIds.length) {
      throw const FavoriteOrderValidationException(
        FavoriteOrderValidationFailure.duplicateIntention,
      );
    }
    return FavoriteOrder._(
      entries: immutableEntries,
      intentionIds: intentionIds,
    );
  }

  const FavoriteOrder._({required this.entries, required this.intentionIds});

  final List<FavoriteOrderEntry> entries;
  final List<IntentionId> intentionIds;
}

/// Куда перемещается избранное намерение. Размещение адресует опору
/// идентификатором, а не индексом видимого списка, поэтому запрос по
/// устаревшему списку не может молча поставить намерение на чужое место.
sealed class FavoritePlacement {
  const FavoritePlacement();
}

/// Первым во всём порядке — перед скрытыми архивированными намерениями.
final class FirstFavoritePlacement extends FavoritePlacement {
  const FirstFavoritePlacement();
}

/// Непосредственно после опорного намерения во всём порядке.
final class AfterFavoritePlacement extends FavoritePlacement {
  const AfterFavoritePlacement(this.anchorId);

  final IntentionId anchorId;
}

sealed class FavoriteOrderMoveResult {
  const FavoriteOrderMoveResult();
}

/// Новый полный порядок, отличный от исходного.
final class FavoriteOrderMoveApplied extends FavoriteOrderMoveResult {
  const FavoriteOrderMoveApplied(this.order);

  final FavoriteOrder order;
}

/// Перемещение не меняет положение намерения среди активных, поэтому полный
/// порядок, включая скрытые архивированные намерения, остаётся прежним.
final class FavoriteOrderMoveWithoutChange extends FavoriteOrderMoveResult {
  const FavoriteOrderMoveWithoutChange();
}

/// Правило отклоняет перемещение, и порядок не меняется.
sealed class FavoriteOrderMoveRejected extends FavoriteOrderMoveResult {
  const FavoriteOrderMoveRejected();
}

/// Перемещаемое намерение указано собственной опорой — ошибка ввода
/// независимо от состояния порядка.
final class FavoriteOrderMoveSelfAnchored extends FavoriteOrderMoveRejected {
  const FavoriteOrderMoveSelfAnchored();
}

/// Перемещаемое или опорное намерение не входит в порядок избранных —
/// конфликт актуального состояния. Архивирование участника конфликтом не
/// является: архивированное избранное сохраняет место.
final class FavoriteOrderMoveMissingParticipant
    extends FavoriteOrderMoveRejected {
  const FavoriteOrderMoveMissingParticipant();
}

/// Единственное выражение правила перестановки избранных намерений.
///
/// Перемещаемое намерение встаёт первым во всём порядке либо
/// непосредственно после опоры; взаимный порядок остальных, включая
/// архивированные, сохраняется. Если ближайшее предшествующее активное
/// намерение уже совпадает с опорой, а при размещении первым активных
/// предшественников нет, видимого изменения нет и полный порядок не
/// меняется: скрытые архивированные намерения не переставляются.
///
/// Функция зависит только от предметных значений и не знает хранилища.
FavoriteOrderMoveResult moveInFavoriteOrder(
  FavoriteOrder order, {
  required IntentionId intentionId,
  required FavoritePlacement placement,
}) {
  final anchorId = switch (placement) {
    FirstFavoritePlacement() => null,
    AfterFavoritePlacement(:final anchorId) => anchorId,
  };
  if (anchorId == intentionId) {
    return const FavoriteOrderMoveSelfAnchored();
  }

  final entries = order.entries;
  final movedIndex = order.intentionIds.indexOf(intentionId);
  if (movedIndex < 0 ||
      (anchorId != null && !order.intentionIds.contains(anchorId))) {
    return const FavoriteOrderMoveMissingParticipant();
  }

  // Для размещения первым опора отсутствует, и сравнение с null означает
  // отсутствие активных предшественников.
  final activePredecessorId = entries
      .take(movedIndex)
      .where((entry) => entry.isActive)
      .map((entry) => entry.intentionId)
      .lastOrNull;
  if (activePredecessorId == anchorId) {
    return const FavoriteOrderMoveWithoutChange();
  }

  final rearranged = [...entries]..removeAt(movedIndex);
  final insertionIndex = anchorId == null
      ? 0
      : rearranged.indexWhere((entry) => entry.intentionId == anchorId) + 1;
  rearranged.insert(insertionIndex, entries[movedIndex]);

  // Архивированная опора непосредственно перед перемещаемым намерением
  // оставляет полный порядок прежним.
  if (insertionIndex == movedIndex) {
    return const FavoriteOrderMoveWithoutChange();
  }
  return FavoriteOrderMoveApplied(FavoriteOrder(rearranged));
}
