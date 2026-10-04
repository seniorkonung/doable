import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';

/// Строка списка избранных намерений: активное избранное намерение без
/// тегов, описания и временных меток, которых Главная не показывает.
final class FavoriteIntentionRow {
  FavoriteIntentionRow({
    required this.id,
    required String title,
    required this.readiness,
    required int activeRelationCount,
  }) : title = IntentionText.normalizeTitle(title),
       activeRelationCount = _requireNonNegativeCount(activeRelationCount);

  final IntentionId id;

  /// Название намерения без изменения.
  final String title;
  final IntentionReadiness readiness;

  /// Точное число активных долговременных связей намерения.
  final int activeRelationCount;

  static int _requireNonNegativeCount(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'activeRelationCount',
        'Количество активных связей не может быть отрицательным.',
      );
    }
    return value;
  }
}

enum FavoriteIntentionsSnapshotValidationFailure {
  duplicateIntention,
  negativeArchivedCount,
}

final class FavoriteIntentionsSnapshotValidationException implements Exception {
  const FavoriteIntentionsSnapshotValidationException(this.failure);

  final FavoriteIntentionsSnapshotValidationFailure failure;
}

/// Полный неизменяемый список избранных намерений на одной ревизии.
///
/// [items] — все активные избранные намерения в едином ручном порядке, каждое
/// ровно один раз по своей идентичности. Архивированные избранные намерения в
/// список не входят и учитываются только числом [archivedCount]: оно отличает
/// отсутствие избранных намерений от случая, когда все они архивированы.
final class FavoriteIntentionsSnapshot {
  factory FavoriteIntentionsSnapshot({
    required List<FavoriteIntentionRow> items,
    required int archivedCount,
    required GraphRevision revision,
  }) {
    if (archivedCount < 0) {
      throw const FavoriteIntentionsSnapshotValidationException(
        FavoriteIntentionsSnapshotValidationFailure.negativeArchivedCount,
      );
    }
    final immutableItems = List<FavoriteIntentionRow>.unmodifiable(items);
    final ids = {for (final row in immutableItems) row.id};
    if (ids.length != immutableItems.length) {
      throw const FavoriteIntentionsSnapshotValidationException(
        FavoriteIntentionsSnapshotValidationFailure.duplicateIntention,
      );
    }
    return FavoriteIntentionsSnapshot._(
      items: immutableItems,
      archivedCount: archivedCount,
      revision: revision,
    );
  }

  const FavoriteIntentionsSnapshot._({
    required this.items,
    required this.archivedCount,
    required this.revision,
  });

  final List<FavoriteIntentionRow> items;
  final int archivedCount;
  final GraphRevision revision;
}

sealed class FavoriteIntentionsReadFailure implements GraphCommandFailure {
  const FavoriteIntentionsReadFailure();
}

final class FavoriteIntentionsUnavailableFailure
    extends FavoriteIntentionsReadFailure {
  const FavoriteIntentionsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class FavoriteIntentionsCorruptionFailure
    extends FavoriteIntentionsReadFailure {
  const FavoriteIntentionsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class FavoriteIntentionsUnexpectedFailure
    extends FavoriteIntentionsReadFailure {
  const FavoriteIntentionsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef FavoriteIntentionsResult =
    GraphResult<FavoriteIntentionsSnapshot, FavoriteIntentionsReadFailure>;
typedef FavoriteIntentionsSuccess =
    GraphResultSuccess<
      FavoriteIntentionsSnapshot,
      FavoriteIntentionsReadFailure
    >;
typedef FavoriteIntentionsError =
    GraphResultFailure<
      FavoriteIntentionsSnapshot,
      FavoriteIntentionsReadFailure
    >;

/// Контракт чтения единого репозитория личного графа для потребителей
/// избранного. Согласованное чтение и проверка данных принадлежат адаптеру
/// графа.
abstract interface class FavoriteReadContract {
  /// Полный список избранных намерений одной транзакции и ревизии: активные
  /// избранные намерения в едином ручном порядке и число архивированных
  /// избранных. Порядок не выводится из времени, названия или идентификатора.
  /// Продолжения, размера порции и предела нет. Отсутствие избранных
  /// намерений — успешный пустой снимок, отличный от отказа чтения. Чтение
  /// не меняет граф.
  Future<FavoriteIntentionsResult> getFavoriteIntentions();
}
